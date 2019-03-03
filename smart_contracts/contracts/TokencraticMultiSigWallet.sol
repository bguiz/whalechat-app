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

/// @title TokencraticMultiSigWallet contract
/// @dev This contract is inspired by the Ethereum Multisignature Wallet contract
///      (https://github.com/gnosis/MultiSigWallet). The code has been changed to allow the holders
///      of an ERC20-compliant token to vote on the execution of submitted transaction, proportionally
///      to the ratio of token's total supply they hold. This contract is intended to be the core of
///      a DAO, allowing the token holders to control other contracts. In the context of WhaleChat,
///      this contract is the `owner` address of the Cashier contract.

import "./WcToken.sol";

contract TokencraticMultiSigWallet {
    using SafeMath for uint256;

    event Confirmation(address sender, uint256 transactionId);
    event Revocation(address indexed sender, uint256 indexed transactionId);
    event Submission(uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event ExecutionFailure(uint256 indexed transactionId);
    event Deposit(address indexed sender, uint256 value);
    event ThresholdChange(uint256 indexed newThreshold);
    event TokenChange();

    mapping (uint256 => Transaction) public transactions;
    mapping (uint256 => mapping (address => bool)) public confirmations;
    uint256 public required;
    uint256 public transactionCount;
    WcToken public token;
    uint256 public threshold;

    // @dev Threshold for voting - akin to "lot size" for shares. ERC20 allows one to own any
    //      arbitrarily small fraction of a token (10e-18), and this poses a problem within the
    //      voting function function, as an attacker may obtain a single token and transfer small
    //      fractions to a large number of addresses which it controls, thereby preventing the
    //      `isConfirmed` function from executing henceforth, by causing it to run out of gas.
    //      The solution to this is to specify that you must own a minimum percentage of the total
    //      token supply in order to be allowed to cast a vote.
    //      The selected threshold is equivalent to `token.MAX_TOKEN_SUPPLY().div(1000)`, which is
    //      0.1% of the total token supply of `WcToken`.
    //      TODO make this modifiable by means of tokencratic owner contract
    uint256 public constant MIN_TOKENS_TO_VOTE = 360 * 10 ** uint256(3) * 10 ** uint256(18);

    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
    }

    modifier onlyMyself() {
        require(msg.sender == address(this), "Only the contract itself can call this function");
        _;
    }

    modifier transactionExists(uint256 _transactionId) {
        require(transactions[_transactionId].destination != 0, "Unknown transaction");
        _;
    }

    modifier confirmed(uint256 _transactionId, address _owner) {
        require(confirmations[_transactionId][_owner], "Transaction is not confirmed");
        _;
    }

    modifier notConfirmed(uint256 _transactionId, address _owner) {
        require(!confirmations[_transactionId][_owner], "Transaction was already confirmed");
        _;
    }

    modifier notExecuted(uint256 _transactionId) {
        require(!transactions[_transactionId].executed, "Transaction was already executed");
        _;
    }

    modifier notNull(address _address) {
        require(_address != 0, "Invalid address");
        _;
    }

    modifier meetsVoteThreshold(address _address) {
        require(
            token.balanceOf(_address) >= MIN_TOKENS_TO_VOTE,
            "Must hold minimum threshold of tokens held to vote"
        );
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function() public
        payable
    {
        if (msg.value > 0)
            emit Deposit(msg.sender, msg.value);
    }

    /// @dev Contract constructor sets the token contract and required confirmation threshold.
    constructor(WcToken _token, uint256 _threshold) public
    {
        token = _token;
        threshold = _threshold;
    }

    /// @dev Change the token contract address. It cannot be a null address (0x0), the current token
    ///      address or the address of this very contract itself
    /// @param _newToken The address of the new token contract
    function setToken(WcToken _newToken) external onlyMyself {
        token = _newToken;
        emit TokenChange();
    }

    /// @dev Change the confirmation threshold. Valid ranges are >= 0 and <= 100. Only the token holders
    ///      themselves can change the threshold.
    /// @param _threshold The ratio of tokens needed to confirm a submitted transaction.
    function setThreshold(uint256 _threshold) external onlyMyself {
        threshold = _threshold;
        emit ThresholdChange(threshold);
    }

    /// @dev Allows token holders to submit a transaction.
    /// @param _destination Transaction target address. If must be non-null.
    /// @param _value Transaction ether value.
    /// @param _data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address _destination, uint256 _value, bytes _data) external
        notNull(_destination)
        returns (uint256 transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: _destination,
            value: _value,
            data: _data,
            executed: false
        });
        transactionCount += 1;

        emit Submission(transactionId);
        return transactionId;
    }

    /// @dev Allows token holders to confirm a transaction. The transaction must have been submitted and
    ///      not yet confirmed by the sender.
    /// @param _transactionId Transaction ID.
    function confirmTransaction(uint256 _transactionId) external
        transactionExists(_transactionId)
        notConfirmed(_transactionId, msg.sender)
        meetsVoteThreshold(msg.sender)
    {
        confirmations[_transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, _transactionId);
    }

    /// @dev Allows a token holder to revoke a confirmation for a transaction. The transaction must have
    ///      been submitted, confirmed by the user and not yet executed.
    /// @param _transactionId Transaction ID.
    function revokeConfirmation(uint256 _transactionId) external
        confirmed(_transactionId, msg.sender)
        notExecuted(_transactionId)
        meetsVoteThreshold(msg.sender)
    {
        confirmations[_transactionId][msg.sender] = false;
        emit Revocation(msg.sender, _transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction. The transactions must not yet have been
    ///      executed.
    /// @param _transactionId Transaction ID.
    function executeTransaction(uint256 _transactionId)
        public
        notExecuted(_transactionId)
    {
        require(isConfirmed(_transactionId), "Transaction is not confirmed");

        Transaction storage txn = transactions[_transactionId];
        txn.executed = true;
        if (txn.destination.call.value(txn.value)(txn.data))
            emit Execution(_transactionId);
        else {
            emit ExecutionFailure(_transactionId);
            txn.executed = false;
        }
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param _transactionId Transaction ID.
    /// @return The transaction's confirmation status.
    function isConfirmed(uint256 _transactionId) public view returns (bool)
    {
        uint256 ratioConfirmed = 0;
        uint256 tokenTotalSupply = token.totalSupply();
        address[] memory tokenHolders = token.holders();
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address tokenHolder = tokenHolders[i];
            if (confirmations[_transactionId][tokenHolder]) {
                ratioConfirmed = ratioConfirmed.add(
                    token.balanceOf(tokenHolder).mul(100).div(tokenTotalSupply)
                );
            }

            if (ratioConfirmed >= threshold) {
                return true;
            }
        }
        return false;
    }

    /// @dev Returns the total number of transactions after filters are applied.
    /// @param _pending Include pending transactions.
    /// @param _executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool _pending, bool _executed) public view returns (uint256 count)
    {
        for (uint256 i = 0; i < transactionCount; i++)
            if ( _pending && !transactions[i].executed ||
                _executed && transactions[i].executed) {
                count += 1;
            }
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param _from Index start position of transaction array.
    /// @param _to Index end position of transaction array.
    /// @param _pending Include pending transactions.
    /// @param _executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint256 _from, uint256 _to, bool _pending, bool _executed) public view
        returns (uint256[] transactionIds)
    {
        uint256[] memory transactionIdsTemp = new uint256[](transactionCount);
        uint256 count = 0;
        uint256 i;
        for (i = 0; i < transactionCount; i++)
            if (   _pending && !transactions[i].executed
                || _executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        transactionIds = new uint256[](_to - _from);
        for (i = _from; i < _to; i++)
            transactionIds[i - _from] = transactionIdsTemp[i];
    }
}
