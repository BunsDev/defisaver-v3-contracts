// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import { IOracle } from "../interfaces/morpho-blue/IOracle.sol";
import { MarketParams } from "../interfaces/morpho-blue/IMorphoBlue.sol";
import { MorphoBlueHelper } from "../actions/morpho-blue/helpers/MorphoBlueHelper.sol";

import { ITrigger } from "../interfaces/ITrigger.sol";
import { AdminAuth } from "../auth/AdminAuth.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/// @title Trigger contract that verifies if current token price ratio is over/under the price ratio specified during subscription
/// @notice This uses the Morpho oracle, which returns the price of the collateral token in terms of the loan token.
/// @dev The trigger expects the price input to be scaled by 1e8
contract MorphoBluePriceTrigger is ITrigger, AdminAuth, MorphoBlueHelper {

    uint256 internal constant TRIGGER_PRICE_SCALE = 1e8;

    enum PriceState {
        OVER,
        UNDER
    }

    struct SubParams {
        MarketParams marketParams;
        uint256 price;
        uint8 state;
    }

    function isTriggered(bytes memory, bytes memory _subData) public view override returns (bool) {
        SubParams memory triggerData = parseSubInputs(_subData);

        uint256 oraclePrice = IOracle(triggerData.marketParams.oracle).price();
        uint256 collDecimals = IERC20(triggerData.marketParams.collateralToken).decimals();
        uint256 loanDecimals = IERC20(triggerData.marketParams.loanToken).decimals();

        /// @dev Examples:
        // 1. wstETH/weth
        // oraclePrice = 1186666219593844843000000000000000000 / 10**(36+18-18) = 1.1866662195938449
        // with trigger price scaling = 1.1866662195938449 * 1e8 = 118666621
        //
        // 2. wstETH/wbtc
        // oraclePrice = 4469382365074666368780959 / 10**(36+8-18) = 0.044693823650746665
        // with trigger price scaling = 0.044693823650746665 * 1e8 = 4469382
        //
        // 3. wstETH/usdc
        // oraclePrice = 4235832459931360140471900072 / 10**(36+6-18) = 4235.83245993136
        // with trigger price scaling = 4235.83245993136 * 1e8 = 423583245
        uint256 currPrice = 
            oraclePrice * TRIGGER_PRICE_SCALE /
            10 ** (ORACLE_PRICE_SCALE + loanDecimals - collDecimals);

        if (PriceState(triggerData.state) == PriceState.OVER) {
            if (currPrice > triggerData.price) return true;
        }

        if (PriceState(triggerData.state) == PriceState.UNDER) {
            if (currPrice < triggerData.price) return true;
        }

        return false;
    }

    //solhint-disable-next-line no-empty-blocks
    function changedSubData(bytes memory _subData) public pure override returns (bytes memory) {}
    
    function isChangeable() public pure override returns (bool) { 
        return false;
    }

    function parseSubInputs(bytes memory _callData) public pure returns (SubParams memory params) {
        params = abi.decode(_callData, (SubParams));
    }
}
