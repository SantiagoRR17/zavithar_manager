// Security-rules tests, run against the Firestore emulator.
//
// These exist because of a finding on 2026-09-13: **the Firebase console and
// the Rules Playground cannot test these rules.** Every collection requires
// `createdAt == request.time`, which only `FieldValue.serverTimestamp()` can
// satisfy, and the Playground's timestamps are typed by hand — so every
// simulated write is denied on the timestamp regardless of its payload. Typing
// `amount: -5` there returns "denied" and proves nothing at all.
//
// The emulator runs a real client SDK, so `serverTimestamp()` resolves to a
// real `request.time`. That is the whole reason this file can exist.
//
// The repository is public (ADR 0010), so these rules are the only thing
// standing between the database and the internet. Until this suite ran, they
// had been observed *accepting* writes and never once *rejecting* one — and a
// control that has never rejected anything is untested.

import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const OWNER = 'owner-uid';
const STRANGER = 'stranger-uid';

let testEnv;
let owner;
let stranger;

before(async () => {
  testEnv = await initializeTestEnvironment({
    // A `demo-` prefix keeps the emulator entirely offline: it never contacts
    // Google and needs no credentials, so this suite cannot touch real data
    // even by accident.
    projectId: 'demo-zavithar',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  owner = testEnv.authenticatedContext(OWNER).firestore();
  stranger = testEnv.authenticatedContext(STRANGER).firestore();
});

after(async () => {
  await testEnv?.cleanup();
});

const path = (collection, id, uid = OWNER) =>
  `users/${uid}/${collection}/${id}`;

/** A transaction that should always be accepted. */
const validTransaction = (overrides = {}) => ({
  amount: 12500,
  type: 'expense',
  category: 'groceries',
  date: Timestamp.fromDate(new Date('2026-09-10T12:00:00Z')),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

const validTodo = (overrides = {}) => ({
  title: 'Renew the passport',
  category: 'home',
  status: 'pending',
  priority: 'medium',
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...overrides,
});

// ---------------------------------------------------------------------------

describe('ownership', () => {
  it('a user may write under their own path', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('transactions', 'own')), validTransaction()),
    );
  });

  it('refuses to read another user\'s data', async () => {
    await assertFails(getDoc(doc(stranger, path('transactions', 'own'))));
  });

  it('refuses to write into another user\'s data', async () => {
    await assertFails(
      setDoc(doc(stranger, path('transactions', 'intruder')), validTransaction()),
    );
  });

  it('refuses an unknown collection, so the project cannot be used as free storage', async () => {
    await assertFails(
      setDoc(doc(owner, path('junk', 'x')), { anything: true }),
    );
  });
});

describe('transactions', () => {
  it('accepts a well-formed one', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('transactions', 'ok')), validTransaction()),
    );
  });

  it('REFUSES a negative amount', async () => {
    // The check the Rules Playground could never actually perform.
    await assertFails(
      setDoc(doc(owner, path('transactions', 'neg')), validTransaction({ amount: -5 })),
    );
  });

  it('REFUSES a zero amount', async () => {
    await assertFails(
      setDoc(doc(owner, path('transactions', 'zero')), validTransaction({ amount: 0 })),
    );
  });

  it('REFUSES an amount that is not a number', async () => {
    await assertFails(
      setDoc(doc(owner, path('transactions', 'str')), validTransaction({ amount: '100' })),
    );
  });

  it('REFUSES an unknown type', async () => {
    await assertFails(
      setDoc(doc(owner, path('transactions', 'type')), validTransaction({ type: 'refund' })),
    );
  });

  it('REFUSES a field the app does not know about', async () => {
    await assertFails(
      setDoc(doc(owner, path('transactions', 'extra')), validTransaction({ hacked: true })),
    );
  });

  it('REFUSES a missing required field', async () => {
    const { category, ...withoutCategory } = validTransaction();
    await assertFails(
      setDoc(doc(owner, path('transactions', 'nocat')), withoutCategory),
    );
  });

  it('REFUSES a client-chosen createdAt', async () => {
    // The rule that stops a client backdating its own audit trail. This is the
    // one the Playground was structurally incapable of testing, because it can
    // only ever supply a client-chosen timestamp.
    await assertFails(
      setDoc(
        doc(owner, path('transactions', 'forged')),
        validTransaction({ createdAt: Timestamp.fromDate(new Date('2020-01-01')) }),
      ),
    );
  });

  it('REFUSES a description past the length limit', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('transactions', 'long')),
        validTransaction({ description: 'x'.repeat(201) }),
      ),
    );
  });

  it('accepts a description inside the limit', async () => {
    await assertSucceeds(
      setDoc(
        doc(owner, path('transactions', 'desc')),
        validTransaction({ description: 'x'.repeat(200) }),
      ),
    );
  });

  it('REFUSES rewriting createdAt on update', async () => {
    await assertFails(
      updateDoc(doc(owner, path('transactions', 'ok')), {
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('backdating into a closed month (ADR 0012)', () => {
  before(async () => {
    await setDoc(doc(owner, path('statements', '2026-07')), {
      periodStart: Timestamp.fromDate(new Date('2026-07-01T00:00:00Z')),
      periodEnd: Timestamp.fromDate(new Date('2026-07-31T23:59:59Z')),
      totalIncome: 1000,
      totalExpense: 400,
      openingBalance: 0,
      closingBalance: 600,
      transactionCount: 2,
      closedAt: serverTimestamp(),
    });
  });

  it('REFUSES a transaction dated inside the closed month', async () => {
    // Unguarded, this money would vanish: it falls before the streamed window
    // and inside no statement, with no error anywhere.
    await assertFails(
      setDoc(
        doc(owner, path('transactions', 'backdated')),
        validTransaction({
          date: Timestamp.fromDate(new Date('2026-07-15T12:00:00Z')),
        }),
      ),
    );
  });

  it('accepts one dated in a month that is still open', async () => {
    await assertSucceeds(
      setDoc(
        doc(owner, path('transactions', 'open-month')),
        validTransaction({
          date: Timestamp.fromDate(new Date('2026-08-15T12:00:00Z')),
        }),
      ),
    );
  });
});

describe('statements', () => {
  const validStatement = (overrides = {}) => ({
    periodStart: Timestamp.fromDate(new Date('2026-06-01T00:00:00Z')),
    periodEnd: Timestamp.fromDate(new Date('2026-06-30T23:59:59Z')),
    totalIncome: 500,
    totalExpense: 200,
    openingBalance: 100,
    closingBalance: 400,
    transactionCount: 3,
    closedAt: serverTimestamp(),
    ...overrides,
  });

  it('accepts one whose balances reconcile', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('statements', '2026-06')), validStatement()),
    );
  });

  it('REFUSES one whose closing balance does not add up', async () => {
    // 100 + 500 - 200 is 400, not 999. A statement that does not follow from
    // its own totals is not a summary of anything, and every later balance is
    // built on top of it.
    await assertFails(
      setDoc(
        doc(owner, path('statements', '2026-05')),
        validStatement({ closingBalance: 999 }),
      ),
    );
  });

  it('REFUSES a negative total', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('statements', '2026-04')),
        validStatement({ totalExpense: -200, closingBalance: 800 }),
      ),
    );
  });

  it('REFUSES editing a closed statement', async () => {
    // Immutability is enforced by the *absence* of an `allow update`. This is
    // the test that proves the absence is doing its job rather than being an
    // oversight nobody noticed.
    await assertFails(
      updateDoc(doc(owner, path('statements', '2026-06')), { totalIncome: 9999 }),
    );
  });

  it('allows deleting one, which is how a month is reopened', async () => {
    await assertSucceeds(deleteDoc(doc(owner, path('statements', '2026-06'))));
  });
});

describe('todos', () => {
  it('accepts a well-formed one', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('todos', 'ok')), validTodo()),
    );
  });

  it('REFUSES an unknown status', async () => {
    await assertFails(
      setDoc(doc(owner, path('todos', 'status')), validTodo({ status: 'maybe' })),
    );
  });

  it('REFUSES a title past the length limit', async () => {
    await assertFails(
      setDoc(doc(owner, path('todos', 'long')), validTodo({ title: 'x'.repeat(121) })),
    );
  });

  it('REFUSES an empty title', async () => {
    await assertFails(
      setDoc(doc(owner, path('todos', 'empty')), validTodo({ title: '' })),
    );
  });

  it('REFUSES a task that follows up on itself', async () => {
    await assertFails(
      setDoc(doc(owner, path('todos', 'selfref')), validTodo({ followUpOf: 'selfref' })),
    );
  });

  it('accepts a follow-up pointing at another task', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('todos', 'child')), validTodo({ followUpOf: 'ok' })),
    );
  });

  it('REFUSES an unknown priority', async () => {
    await assertFails(
      setDoc(doc(owner, path('todos', 'prio')), validTodo({ priority: 'urgent' })),
    );
  });
});

describe('recurring', () => {
  const validRule = (overrides = {}) => ({
    amount: 900000,
    type: 'expense',
    category: 'rent',
    cadence: 'monthly',
    anchorDay: 1,
    nextRunAt: Timestamp.fromDate(new Date('2026-10-01T09:00:00Z')),
    active: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('accepts a well-formed rule', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('recurring', 'rent')), validRule()),
    );
  });

  it('REFUSES an unknown cadence', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('recurring', 'odd')),
        validRule({ cadence: 'fortnightly' }),
      ),
    );
  });

  it('REFUSES an anchor day outside 1-31', async () => {
    await assertFails(
      setDoc(doc(owner, path('recurring', 'zero')), validRule({ anchorDay: 0 })),
    );
    await assertFails(
      setDoc(doc(owner, path('recurring', 'big')), validRule({ anchorDay: 32 })),
    );
  });

  it('REFUSES a non-integer anchor day', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('recurring', 'frac')),
        validRule({ anchorDay: 1.5 }),
      ),
    );
  });

  it('REFUSES a zero or negative amount', async () => {
    await assertFails(
      setDoc(doc(owner, path('recurring', 'free')), validRule({ amount: 0 })),
    );
  });

  it('REFUSES active as a string', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('recurring', 'str')),
        validRule({ active: 'true' }),
      ),
    );
  });

  it('accepts a paused rule', async () => {
    await assertSucceeds(
      setDoc(
        doc(owner, path('recurring', 'paused')),
        validRule({ active: false }),
      ),
    );
  });
});

describe('budgets', () => {
  const validBudget = (overrides = {}) => ({
    category: 'groceries',
    monthlyLimit: 400000,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('accepts a well-formed one', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('budgets', 'groceries')), validBudget()),
    );
  });

  it('REFUSES a limit of zero', async () => {
    // Not a budget, a ban — and nothing here could enforce one.
    await assertFails(
      setDoc(
        doc(owner, path('budgets', 'rent')),
        validBudget({ category: 'rent', monthlyLimit: 0 }),
      ),
    );
  });

  it('REFUSES a negative limit', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('budgets', 'health')),
        validBudget({ category: 'health', monthlyLimit: -1 }),
      ),
    );
  });

  it('REFUSES a category that disagrees with the document id', async () => {
    // Otherwise a document could claim to budget `rent` while living under
    // `groceries`, and every screen would disagree about which one it was.
    await assertFails(
      setDoc(
        doc(owner, path('budgets', 'transport')),
        validBudget({ category: 'rent' }),
      ),
    );
  });

  it('REFUSES an unknown field', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('budgets', 'study')),
        validBudget({ category: 'study', rollover: true }),
      ),
    );
  });

  it('allows deleting one', async () => {
    await assertSucceeds(deleteDoc(doc(owner, path('budgets', 'groceries'))));
  });
});

describe('savings and liabilities', () => {
  const validGoal = (overrides = {}) => ({
    name: 'New laptop',
    targetAmount: 3000000,
    currentAmount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  const validLiability = (overrides = {}) => ({
    name: 'Card',
    type: 'credit card',
    originalAmount: 1000000,
    remainingAmount: 400000,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('accepts a well-formed savings goal', async () => {
    await assertSucceeds(setDoc(doc(owner, path('savings', 'ok')), validGoal()));
  });

  it('REFUSES a goal with no target', async () => {
    await assertFails(
      setDoc(doc(owner, path('savings', 'zero')), validGoal({ targetAmount: 0 })),
    );
  });

  it('REFUSES a negative saved amount', async () => {
    await assertFails(
      setDoc(doc(owner, path('savings', 'neg')), validGoal({ currentAmount: -1 })),
    );
  });

  it('accepts over-saving, which is real', async () => {
    await assertSucceeds(
      setDoc(
        doc(owner, path('savings', 'over')),
        validGoal({ currentAmount: 4000000 }),
      ),
    );
  });

  it('accepts a debt grown past what was borrowed', async () => {
    // Deliberately allowed: interest and late fees make this real, and an app
    // that refuses to record it is lying about the situation it exists to
    // track.
    await assertSucceeds(
      setDoc(
        doc(owner, path('liabilities', 'grown')),
        validLiability({ remainingAmount: 1200000 }),
      ),
    );
  });

  it('REFUSES an impossible interest rate', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('liabilities', 'rate')),
        validLiability({ interestRate: 101 }),
      ),
    );
  });
});

describe('categories (Milestone 4)', () => {
  const validCategory = (overrides = {}) => ({
    kind: 'expense',
    key: 'groceries',
    label: 'Groceries',
    sortOrder: 100,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  });

  it('accepts a well-formed category', async () => {
    await assertSucceeds(
      setDoc(doc(owner, path('categories', 'expense:groceries')), validCategory()),
    );
  });

  it('accepts a todo category under the same key as an expense one', async () => {
    // `home` is both a plausible expense category and one of the four todo
    // categories. The kind in the ID is what lets both exist.
    await assertSucceeds(
      setDoc(
        doc(owner, path('categories', 'expense:home')),
        validCategory({ key: 'home', label: 'Home' }),
      ),
    );
    await assertSucceeds(
      setDoc(
        doc(owner, path('categories', 'todo:home')),
        validCategory({ kind: 'todo', key: 'home', label: 'Home' }),
      ),
    );
  });

  it('REFUSES a document whose ID disagrees with its fields', async () => {
    // Otherwise a document could claim to be an income category while living
    // among the expense ones, and every screen would disagree about which list
    // it belongs to.
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:rent')),
        validCategory({ kind: 'income', key: 'rent' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:rent')),
        validCategory({ key: 'mortgage' }),
      ),
    );
  });

  it('REFUSES an unknown kind', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'project:thing')),
        validCategory({ kind: 'project', key: 'thing' }),
      ),
    );
  });

  it('REFUSES an empty or oversized label', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:blank')),
        validCategory({ key: 'blank', label: '' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:long')),
        validCategory({ key: 'long', label: 'x'.repeat(41) }),
      ),
    );
  });

  it('REFUSES a negative or non-integer sort order', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:neg')),
        validCategory({ key: 'neg', sortOrder: -1 }),
      ),
    );
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:frac')),
        validCategory({ key: 'frac', sortOrder: 1.5 }),
      ),
    );
  });

  it('REFUSES an unknown field', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:extra')),
        validCategory({ key: 'extra', colour: '#ff0000' }),
      ),
    );
  });

  it('REFUSES a backdated createdAt', async () => {
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:back')),
        validCategory({ key: 'back', createdAt: Timestamp.fromMillis(0) }),
      ),
    );
  });

  it('accepts a rename', async () => {
    await assertSucceeds(
      updateDoc(doc(owner, path('categories', 'expense:groceries')), {
        label: 'Mercado',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('accepts a reorder', async () => {
    await assertSucceeds(
      updateDoc(doc(owner, path('categories', 'expense:groceries')), {
        sortOrder: 250,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('**REFUSES changing the key**', async () => {
    // The property this whole design rests on. Every transaction ever written
    // holds the key, and nothing server-side can rewrite them — so a key that
    // could change would silently orphan history.
    await assertFails(
      updateDoc(doc(owner, path('categories', 'expense:groceries')), {
        key: 'mercado',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('REFUSES changing the kind', async () => {
    await assertFails(
      updateDoc(doc(owner, path('categories', 'expense:groceries')), {
        kind: 'income',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('REFUSES rewriting createdAt', async () => {
    await assertFails(
      updateDoc(doc(owner, path('categories', 'expense:groceries')), {
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('accepts deleting a category', async () => {
    await assertSucceeds(
      deleteDoc(doc(owner, path('categories', 'expense:home'))),
    );
  });

  it('REFUSES a stranger entirely', async () => {
    await assertFails(
      getDoc(doc(stranger, path('categories', 'expense:groceries'))),
    );
    await assertFails(
      setDoc(doc(stranger, path('categories', 'expense:x')), validCategory({ key: 'x' })),
    );
  });

  it('**REFUSES an invalid category even though the catch-all matches it**', async () => {
    // The regression guard for the OR-ing gotcha. `categories` is a known
    // collection, so `match /{collection}/{docId}` also matches this path; if
    // it were not excluded there, every check above would pass by accident.
    await assertFails(
      setDoc(
        doc(owner, path('categories', 'expense:junk')),
        { anything: 'at all' },
      ),
    );
  });
});
