// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import { IAddressesRegistry } from "../../../interfaces/liquityV2/IAddressesRegistry.sol";
import { IStabilityPool } from "../../../interfaces/liquityV2/IStabilityPool.sol";

import { LiquityV2Helper } from "../helpers/LiquityV2Helper.sol";
import { ActionBase } from "../../ActionBase.sol";
import { TokenUtils } from "../../../utils/TokenUtils.sol";

/// @title Deposits a token to the LiquityV2 Stability Pool
contract LiquityV2SPDeposit is ActionBase, LiquityV2Helper {
    using TokenUtils for address;

    struct Params {
        address market;
        address from;
        address boldGainTo;
        address collGainTo;
        uint256 amount;
        bool doClaim;
    }

    /// @inheritdoc ActionBase
    function executeAction(
        bytes memory _callData,
        bytes32[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual override returns (bytes32) {
        Params memory params = parseInputs(_callData);

        params.market = _parseParamAddr(params.market, _paramMapping[0], _subData, _returnValues);
        params.from = _parseParamAddr(params.from, _paramMapping[1], _subData, _returnValues);
        params.boldGainTo = _parseParamAddr(params.boldGainTo, _paramMapping[2], _subData, _returnValues);
        params.collGainTo = _parseParamAddr(params.collGainTo, _paramMapping[3], _subData, _returnValues);
        params.amount = _parseParamUint(params.amount, _paramMapping[4], _subData, _returnValues);
        params.doClaim = _parseParamUint(
            params.doClaim ? 1 : 0,
            _paramMapping[5],
            _subData,
            _returnValues
        ) == 1;

        (uint256 depositedAmount, bytes memory logData) = _spDeposit(params);
        emit ActionEvent("LiquityV2SPDeposit", logData);
        return bytes32(depositedAmount);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes memory _callData) public payable override {
        Params memory params = parseInputs(_callData);
        (, bytes memory logData) = _spDeposit(params);
        logger.logActionDirectEvent("LiquityV2SPDeposit", logData);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    /*//////////////////////////////////////////////////////////////
                            ACTION LOGIC
    //////////////////////////////////////////////////////////////*/
    function _spDeposit(Params memory _params) internal returns (uint256, bytes memory) {
        IStabilityPool pool = IStabilityPool(IAddressesRegistry(_params.market).stabilityPool());

        uint256 boldGain = _params.doClaim
            ? pool.getDepositorYieldGain(address(this))
            : 0;

        uint256 collGain = _params.doClaim
            ? pool.getDepositorCollGain(address(this)) + pool.stashedColl(address(this))
            : 0;

        _params.amount = BOLD_ADDR.pullTokensIfNeeded(_params.from, _params.amount);
        pool.provideToSP(_params.amount, _params.doClaim);

        if (_params.doClaim) {
            address collToken = IAddressesRegistry(_params.market).collToken();
            BOLD_ADDR.withdrawTokens(_params.boldGainTo, boldGain);
            collToken.withdrawTokens(_params.collGainTo, collGain);
        }

        return (_params.amount, abi.encode(_params));
    }

    function parseInputs(bytes memory _callData) public pure returns (Params memory params) {
        params = abi.decode(_callData, (Params));
    }
}
