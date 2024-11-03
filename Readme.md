# StakingMining

## Test
``
forge test
``

## Logs
```
Ran 11 tests for test/StakingMining.t.sol:StakingMiningTest
[PASS] testFuzz_Stake(uint256) (runs: 1000, μ: 107186, ~: 107234)
[PASS] testFuzz_UnstakePartial(uint256,uint256) (runs: 1000, μ: 114482, ~: 114379)
[PASS] test_ClaimReward() (gas: 187021)
[PASS] test_ConvertEsRNTtoRNT() (gas: 176493)
[PASS] test_ConvertEsRNTtoRNTAfterFullPeriod() (gas: 175073)
[PASS] test_InitialState() (gas: 18419)
[PASS] test_RewardCalculation() (gas: 103831)
[PASS] test_Unstake() (gas: 111886)
[PASS] test_UnstakeInvalidAmount() (gas: 105946)
Suite result: ok. 11 passed; 0 failed; 0 skipped; finished in 131.67ms (249.25ms CPU time)

Ran 1 test suite in 134.85ms (131.67ms CPU time): 11 tests passed, 0 failed, 0 skipped (11 total tests)
```
