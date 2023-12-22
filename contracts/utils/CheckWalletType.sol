// SPDX-License-Identifier: MIT

pragma solidity =0.8.10;

contract CheckWalletType {
    // TODO: should it be a better check
    function isDSProxy(address _proxy) internal view returns (bool) {
        (bool success, bytes memory response) = _proxy.staticcall(abi.encodeWithSignature("nonce()"));
        if (!success) revert();

        // DSProxy has an empty fallback will return success and 0x0 in response, gnosis has nonce() in all version
        if (response.length == 0) return true;

        return false;
    }
}