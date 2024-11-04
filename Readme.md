# StakingMining

## Test
``
forge test
``

## Logs
```
Ran 13 tests for test/StakingMining.t.sol:StakingMiningTest
[PASS] testFuzz_Stake(uint256) (runs: 1000, μ: 112027, ~: 112081)
[PASS] testFuzz_UnstakePartial(uint256,uint256) (runs: 1000, μ: 119552, ~: 119456)
[PASS] test_ClaimReward() (gas: 236874)
[PASS] test_ClaimReward_Alternative() (gas: 241402)
[PASS] test_ConvertEsRNT() (gas: 227562)
[PASS] test_ConvertEsRNTAfterFullPeriod() (gas: 226408)
[PASS] test_InitialState() (gas: 23933)
[PASS] test_RewardCalculation() (gas: 108602)
[PASS] test_Stake() (gas: 109905)
[PASS] test_StakePermit() (gas: 205004)
[PASS] test_StakeZeroAmount() (gas: 18566)
[PASS] test_Unstake() (gas: 116880)
[PASS] test_UnstakeInvalidAmount() (gas: 110706)
Suite result: ok. 13 passed; 0 failed; 0 skipped; finished in 83.38ms (160.19ms CPU time)

Ran 1 test suite in 86.43ms (83.38ms CPU time): 13 tests passed, 0 failed, 0 skipped (13 total tests)
```
