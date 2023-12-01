// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "ds-test/test.sol";

import "../TokenAddresses.sol";
import "../CheatCodes.sol";

import "../utils/Tokens.sol";
import "../utils/CompUser.sol";
import "../utils/BundleBuilder.sol";
import "../utils/RegistryUtils.sol";
import "../utils/ActionsUtils.sol";
import "../utils/Strategies.sol";

import "../../contracts/core/strategy/StrategyModel.sol";
import "../../contracts/core/strategy/StrategyExecutor.sol";
import "../../contracts/triggers/CompV3RatioTrigger.sol";
import "../../contracts/actions/fee/GasFeeTaker.sol";
import "../../contracts/actions/exchange/DFSSell.sol";
import "../../contracts/actions/compoundV3/CompV3SubProxy.sol";
import "../../contracts/actions/checkers/CompV3RatioCheck.sol";
import "../../contracts/actions/flashloan/FLAction.sol";
import "forge-std/console.sol";

contract TestCompV3Automation is
    DSTest,
    DSMath,
    Tokens,
    RegistryUtils,
    ActionsUtils,
    Strategies
{
    CompUser user1;
    address proxy;

    StrategyExecutor executor;
    CompV3RatioTrigger trigger;
    FLAction flAction;

    StrategyModel.StrategySub repaySub;
    uint256 repaySubId;
    uint64 repayBundleId;

    StrategyModel.StrategySub boostSub;
    uint256 boostSubId;
    uint64 boostBundleId;

    uint256 boostGasCost = 950_000;
    uint256 repayGasCost = 950_000;

    uint256 boostFLGasCost = 1_350_000;
    uint256 repayFLGasCost = 1_350_000;

    constructor() {
        trigger = new CompV3RatioTrigger();
        flAction = new FLAction();
        user1 = new CompUser();
        proxy = user1.proxyAddr();
        executor = StrategyExecutor(getAddr("StrategyExecutorID"));

        _redeployContracts();
        vm.etch(SUB_STORAGE_ADDR, address(new SubStorage()).code);
        addBotCaller(address(this));
        _initRepayBundle();
        _initBoostBundle();
        _createCompPosition();
        _subToAutomationBundles();
    }

    function _redeployContracts() internal {
        redeploy("CompV3Supply", address(new CompV3Supply()));
        redeploy("CompV3Withdraw", address(new CompV3Withdraw()));
        redeploy("CompV3Borrow", address(new CompV3Borrow()));
        redeploy("CompV3Payback", address(new CompV3Payback()));
        redeploy("CompV3RatioTrigger", address(trigger));
        redeploy("DFSSell", address(new DFSSell()));
        redeploy("GasFeeTaker", address(new GasFeeTaker()));
        redeploy("CompV3RatioCheck", address(new CompV3RatioCheck()));
        redeploy("FLAction", address(flAction));
    }

    function _initRepayBundle() internal {
        uint256 repayId = createCompV3Repay();
        uint256 repayFLId = createCompV3FLRepay();

        BundleBuilder bundleBuilder = new BundleBuilder();

        uint64[] memory repayIds = new uint64[](2);
        repayIds[0] = uint64(repayId);
        repayIds[1] = uint64(repayFLId);
        repayBundleId = uint64(bundleBuilder.init(repayIds));
    }

    function _initBoostBundle() internal {
        uint256 boostId = createCompV3Boost();
        uint256 boostFLId = createCompV3FLBoost();

        BundleBuilder bundleBuilder = new BundleBuilder();

        uint64[] memory boostIds = new uint64[](2);
        boostIds[0] = uint64(boostId);
        boostIds[1] = uint64(boostFLId);
        boostBundleId = uint64(bundleBuilder.init(boostIds));
    }

    function _createCompPosition() internal {
        gibTokens(user1.proxyAddr(), TokenAddresses.WETH_ADDR, 1000 ether);
        uint ethAmount = amountInUSDPrice(TokenAddresses.WETH_ADDR, 15_000);
        user1.supply(TokenAddresses.COMET_USDC, TokenAddresses.WETH_ADDR, ethAmount);
        user1.borrow(TokenAddresses.COMET_USDC, 10_000e6);
    }

    function _subToAutomationBundles() internal {
        CompV3SubProxy subProxy = new CompV3SubProxy(repayBundleId, boostBundleId, 0, 0);

        uint128 minRatio = 180e16;
        uint128 maxRatio = 220e16;
        uint128 targetRatioBoost = 200e16;
        uint128 targetRatioRepay = 200e16;

        CompV3SubProxy.CompV3SubData memory params = user1.subToAutomationBundles(
            address(subProxy), minRatio, maxRatio, targetRatioBoost, targetRatioRepay
        );

        repaySubId = SubStorage(SUB_STORAGE_ADDR).getSubsCount() - 2;
        boostSubId = SubStorage(SUB_STORAGE_ADDR).getSubsCount() - 1;

        repaySub = subProxy.formatRepaySub(params, proxy, address(0));
        boostSub = subProxy.formatBoostSub(params, proxy, address(0));
    }

    //////////////////////////////// TESTs /////////////////////////////////////////////

    function testCompV3RepayStrategy() public {
        uint wethAmount = amountInUSDPrice(TokenAddresses.WETH_ADDR, 1_000);
        uint256 repayIndex = 0;

        uint256 borrowAmountBefore = IComet(TokenAddresses.COMET_USDC).borrowBalanceOf(proxy);
        uint256 txFeeBalanceBefore = IERC20(TokenAddresses.WETH_ADDR).balanceOf(TokenAddresses.FEE_RECEIVER);

        bytes[] memory _triggerCallData = new bytes[](1);

        bytes[] memory _actionsCallData = new bytes[](5);
        _actionsCallData[0] = compV3WithdrawEncode(TokenAddresses.COMET_USDC, proxy, TokenAddresses.WETH_ADDR, wethAmount);
        _actionsCallData[1] = sellEncode(TokenAddresses.WETH_ADDR, TokenAddresses.USDC_ADDR, 0, proxy, proxy, TokenAddresses.UNI_V2_WRAPPER);
        _actionsCallData[2] = gasFeeEncode(repayGasCost, TokenAddresses.USDC_ADDR);
        _actionsCallData[3] = compV3PaybackEncode(TokenAddresses.COMET_USDC, proxy, 0);
        _actionsCallData[4] = compV3RatioCheckEncode(0, 0, address(0));

        uint beforeRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        executor.executeStrategy(repaySubId, repayIndex, _triggerCallData, _actionsCallData, repaySub);

        uint afterRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);
        uint256 txFeeBalanceAfter = IERC20(TokenAddresses.WETH_ADDR).balanceOf(TokenAddresses.FEE_RECEIVER);
        uint256 borrowAmountAfter = IComet(TokenAddresses.COMET_USDC).borrowBalanceOf(proxy);

        uint amountAfterFee = wethAmount - (wethAmount / 400);

        // assert exchange fee
        assertEq(wethAmount - amountAfterFee, txFeeBalanceAfter - txFeeBalanceBefore);
        assertGt(borrowAmountBefore, borrowAmountAfter);
        assertGt(afterRatio, beforeRatio);
    }

    function testCompV3FLRepayStrategy() public {
        uint wethAmount = amountInUSDPrice(TokenAddresses.WETH_ADDR, 1_000);

        uint256 repayIndex = 1;

        bytes[] memory _triggerCallData = new bytes[](1);

        bytes[] memory _actionsCallData = new bytes[](6);
        _actionsCallData[0] = flActionEncode(TokenAddresses.WETH_ADDR, wethAmount, FLSource.BALANCER);
        _actionsCallData[1] = sellEncode(TokenAddresses.WETH_ADDR, TokenAddresses.USDC_ADDR, wethAmount, proxy, proxy, TokenAddresses.UNI_V2_WRAPPER);
        _actionsCallData[2] = gasFeeEncode(repayFLGasCost, TokenAddresses.USDC_ADDR);
        _actionsCallData[3] = compV3PaybackEncode(TokenAddresses.COMET_USDC, proxy, 0);
        _actionsCallData[4] = compV3WithdrawEncode(TokenAddresses.COMET_USDC, address(flAction), TokenAddresses.WETH_ADDR, wethAmount);
        _actionsCallData[5] = compV3RatioCheckEncode(0, 0, address(0));

        uint beforeRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        executor.executeStrategy(repaySubId, repayIndex, _triggerCallData, _actionsCallData, repaySub);

        uint afterRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);
        assertGt(afterRatio, beforeRatio);
    }

    function testCompV3BoostStrategy() public {
        uint256 usdcAmount = 500e6;
        uint256 boostIndex = 0;

        uint ethAmount = amountInUSDPrice(TokenAddresses.WETH_ADDR, 15_000);
        user1.supply(TokenAddresses.COMET_USDC, TokenAddresses.WETH_ADDR, ethAmount);

        bytes[] memory _triggerCallData = new bytes[](1);

        bytes[] memory _actionsCallData = new bytes[](5);
        _actionsCallData[0] = compV3BorrowEncode(TokenAddresses.COMET_USDC, usdcAmount, proxy);
        _actionsCallData[1] = sellEncode(TokenAddresses.USDC_ADDR, TokenAddresses.WETH_ADDR, 0, proxy, proxy, TokenAddresses.UNI_V2_WRAPPER);
        _actionsCallData[2] = gasFeeEncode(boostGasCost, TokenAddresses.WETH_ADDR);
        _actionsCallData[3] = compV3SupplyEncode(TokenAddresses.COMET_USDC, TokenAddresses.WETH_ADDR, 0, proxy);
        _actionsCallData[4] = compV3RatioCheckEncode(0, 0, address(0));

        uint beforeRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        executor.executeStrategy(boostSubId, boostIndex, _triggerCallData, _actionsCallData, boostSub);
        uint afterRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        assertGt(beforeRatio, afterRatio);
    }

    function testCompV3BoostFLStrategy() public {
        uint256 usdcAmount = 500e6;
        uint256 boostIndex = 1;

        uint ethAmount = amountInUSDPrice(TokenAddresses.WETH_ADDR, 15_000);
        user1.supply(TokenAddresses.COMET_USDC, TokenAddresses.WETH_ADDR, ethAmount);

        bytes[] memory _triggerCallData = new bytes[](1);

        bytes[] memory _actionsCallData = new bytes[](6);
        _actionsCallData[0] = flActionEncode(TokenAddresses.USDC_ADDR, usdcAmount, FLSource.BALANCER);
        _actionsCallData[1] = sellEncode(TokenAddresses.USDC_ADDR, TokenAddresses.WETH_ADDR, usdcAmount, proxy, proxy, TokenAddresses.UNI_V2_WRAPPER);
        _actionsCallData[2] = gasFeeEncode(boostFLGasCost, TokenAddresses.WETH_ADDR);
        _actionsCallData[3] = compV3SupplyEncode(TokenAddresses.COMET_USDC, TokenAddresses.WETH_ADDR, 0, proxy);
        _actionsCallData[4] = compV3BorrowEncode(TokenAddresses.COMET_USDC, usdcAmount, address(flAction));
        _actionsCallData[5] = compV3RatioCheckEncode(0, 0, address(0));

        uint beforeRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        executor.executeStrategy(boostSubId, boostIndex, _triggerCallData, _actionsCallData, boostSub);

        uint afterRatio = trigger.getSafetyRatio(TokenAddresses.COMET_USDC, proxy);

        assertGt(beforeRatio, afterRatio);
    }
}
