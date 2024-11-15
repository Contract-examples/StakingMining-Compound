# StakingMining Compound


## Test
```
forge test -vv
```

## Logs
```
Ran 3 tests for test/Staking.t.sol:StakingTest
[PASS] test_MultipleUsersStaking() (gas: 290477)
Logs:
  Total reward: 500000000000000000000
  Alice expected: 333333333333333333333
  Bob expected: 166666666666666666666
  Alice actual: 333333333333333333333
  Bob actual: 166666666666666666666

[PASS] test_SingleUserStaking() (gas: 188079)
Logs:
  Expected reward: 500000000000000000000
  Actual reward: 500000000000000000000

[PASS] test_StakeUnstakeRewards() (gas: 211132)
Logs:
  First phase reward claimed: 250000000000000000000
  Second phase expected reward: 125000000000000000000

=== Final Results ===
  First phase reward: 250000000000000000000
  Second phase reward: 125000000000000000000
  Total reward: 375000000000000000000
  Expected total reward: 375000000000000000000

Suite result: ok. 3 passed; 0 failed; 0 skipped; finished in 1.75ms (1.14ms CPU time)

Ran 1 test suite in 9.20ms (1.75ms CPU time): 3 tests passed, 0 failed, 0 skipped (3 total tests)
```
