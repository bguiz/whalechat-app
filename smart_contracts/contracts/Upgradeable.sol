/*

Copyright (c) 2019 WhaleChat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

pragma solidity 0.4.25;

/// @title Upgradeable contract
/// @dev This is to be inherited by the `Cashier` contract to allow deploying further versions of the
///      contract in the future. Only the `owner` address can upgrade. When upgrading, all ether in the
///      contract are transfered to the new contract address. The new contract address needs to be
///      stored in the upgraded contract so the WhaleChat app can iterate through the chain of upgraded
///      contracts up to the last version. An `Upgradeable` contract can only be upgraded once.

import "../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract Upgradeable is Ownable {

    bool public upgraded;
    address public newContractAddress;

    event ContractUpgrade(address indexed newContractAddress);

    function() external payable {}

    modifier notUpgraded() {
        require(!upgraded, "Function cannot be called because contract was upgraded");
        _;
    }

    /// @dev Upgrades the contract. Sends all ether to the new contract.
    ///      The new contract address cannot be null or the address of the contract itself.
    /// @param  _newContractAddress The address of the contract to upgrade to.
    function upgrade(address _newContractAddress) external onlyOwner notUpgraded {
        require(_newContractAddress != address(0), "New contract adress cannot be null");
        require(_newContractAddress != address(this), "Contract cannot upgrade to itself");
        newContractAddress = _newContractAddress;
        if (address(this).balance > 0) {
            _newContractAddress.transfer(address(this).balance);
        }
        upgraded = true;
        emit ContractUpgrade(newContractAddress);
    }
}
