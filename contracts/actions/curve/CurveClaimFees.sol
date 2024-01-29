// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../ActionBase.sol";
import "./helpers/CurveHelper.sol";
import "../../utils/TokenUtils.sol";

contract CurveClaimFees is ActionBase, CurveHelper {
    using TokenUtils for address;

    struct Params {
        address claimFor;   // Address for which to claim fees
        address receiver;   // Address that will receive the tokens
    }

    function executeAction(
        bytes memory _callData,
        bytes32[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual override returns (bytes32) {
        Params memory params = parseInputs(_callData);
        params.claimFor = _parseParamAddr(params.claimFor, _paramMapping[0], _subData, _returnValues);
        params.receiver = _parseParamAddr(params.receiver, _paramMapping[1], _subData, _returnValues);

        (uint256 claimed, bytes memory logData) = _curveClaimFees(params);
        emit ActionEvent("CurveClaimFees", logData);
        return bytes32(claimed);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes memory _callData) public payable virtual override {
        Params memory params = parseInputs(_callData);
        (, bytes memory logData) = _curveClaimFees(params);
        logger.logActionDirectEvent("CurveClaimFees", logData);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    /// @notice Claims 3Crv rewards from Fee Distributor
    /// @dev if _claimFor != _receiver the _claimFor address needs to approve the user's wallet to pull 3Crv token
    function _curveClaimFees(Params memory _params) internal returns (uint256 claimed, bytes memory logData) {
        claimed = FeeDistributor.claim(_params.claimFor);

        if (_params.claimFor != _params.receiver) {
            CRV_3CRV_TOKEN_ADDR.pullTokensIfNeeded(_params.claimFor, claimed);
            CRV_3CRV_TOKEN_ADDR.withdrawTokens(_params.receiver, claimed);
        }

        logData = abi.encode(_params, claimed);
    }

    function parseInputs(bytes memory _callData) internal pure returns (Params memory params) {
        params = abi.decode(_callData, (Params));
    }
}