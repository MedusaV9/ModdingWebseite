import { test } from 'node:test'
import assert from 'node:assert/strict'
import { intQuery } from '../../src/api/helpers.ts'

test('intQuery parses valid numbers', () => {
  assert.equal(intQuery('50', 200, 1, 2000), 50)
  assert.equal(intQuery('0', 10, 0, 100), 0)
})

test('intQuery falls back to default for non-numeric input', () => {
  assert.equal(intQuery('abc', 200, 1, 2000), 200)
  assert.equal(intQuery('12abc', 200, 1, 2000), 200)
  assert.equal(intQuery({}, 200, 1, 2000), 200)
})

test('intQuery uses default when value is missing', () => {
  assert.equal(intQuery(undefined, 200, 1, 2000), 200)
  assert.equal(intQuery(null, 200, 1, 2000), 200)
})

test('intQuery clamps to min/max bounds', () => {
  assert.equal(intQuery('999999', 200, 1, 2000), 2000)
  assert.equal(intQuery('-5', 200, 1, 2000), 1)
})

test('intQuery truncates decimals', () => {
  assert.equal(intQuery('3.9', 0, 0, 10), 3)
})

test('intQuery rejects Infinity', () => {
  assert.equal(intQuery('Infinity', 200, 1, 2000), 200)
})
