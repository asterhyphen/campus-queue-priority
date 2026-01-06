const { expect } = require('chai');
const index = require('../index');

describe('helpers', () => {
  it('computePriorityFromEmail: 4MT* emails should be lower priority (2)', () => {
    expect(index._test.computePriorityFromEmail('4MT2021@mite.ac.in')).to.equal(2);
    expect(index._test.computePriorityFromEmail('4mtX@mite.ac.in')).to.equal(2);
  });

  it('computePriorityFromEmail: non-4MT emails should be higher priority (1)', () => {
    expect(index._test.computePriorityFromEmail('teacher@mite.ac.in')).to.equal(1);
    expect(index._test.computePriorityFromEmail('alice@asterhyphen.xyz')).to.equal(1);
  });

  it('computePriorityFromEmail: fallback when no email returns 2', () => {
    expect(index._test.computePriorityFromEmail(null)).to.equal(2);
    expect(index._test.computePriorityFromEmail(undefined)).to.equal(2);
  });
});
