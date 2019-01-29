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

/// @title Cashier contract
/// @dev This is an ERC721-compliant contract whose tokens, called "tickets", allow their buyer to display a
///      message in the whales-only rooms in the WhaleChat app. These messages can be used to advertise services.
///      Only the the `owner` address of this contract can issue new tickets. The owner of this contract is a
///      multisig contract controlled by the WhaleChat token holders. Anybody can buy a ticket. The revenue earned
///      from selling tickets is distributed among WhaleChat token holders proportionally to their share
///      share of the total token supply. This contract is upgradeable.

import "../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "./Upgradeable.sol";
import "./WcToken.sol";

contract Cashier is ERC721, Ownable, Upgradeable {
    using SafeMath for uint256;

    uint256 public constant MAX_MESSAGE_LENGTH = 64;

    struct Ticket {
        uint256 numBlocksExpiry;
        uint256 sellingPrice;
        string message;
        uint256 expiryBlock;
    }

    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => address) public ticketOwner;
    uint256 public numTickets;
    WcToken public token;
    uint256 public cashEarnedSinceLastUpdate;
    mapping(address => uint256) public withdrawableCash;
    mapping(address => bool) public withdrawn;

    event TicketIssued(uint256 indexed ticketId, uint256 numBlocksExpiry, uint256 sellingPrice);
    event TicketBought(uint256 indexed ticketId, address indexed buyer, uint256 expiryBlock, string message);
    event TokenDistributionUpdated();
    event CashWithdrawn(address withdrawer);

    constructor(WcToken _token) public {
        token = _token;
    }

    // @dev Issues a new ticket. This function can be called only by the contract owner.
    //      This function is disabled after contract is upgraded.
    // @param _numBlocksExpiry  Number of blocks since the ticket purchase until the ticket with be valid.
    // @param _sellingPrice     The ticket selling price.
    function issueTicket(uint256 _numBlocksExpiry, uint256 _sellingPrice) external onlyOwner notUpgraded
        returns (uint256 ticketId) {
        require(_numBlocksExpiry > 0, "Expiry cannot be zero");
        require(_sellingPrice > 0, "Price cannot be zero");

        Ticket memory ticket = Ticket({
            numBlocksExpiry: _numBlocksExpiry,
            sellingPrice: _sellingPrice,
            message: "",
            expiryBlock: 0
        });
        
        ticketId = numTickets;
        tickets[ticketId] = ticket;
        numTickets++;

        emit TicketIssued(ticketId, _numBlocksExpiry, _sellingPrice);
        return ticketId;
    }

    // @dev A ticket is purchased by the caller of this function, which can be anyone.
    //      This function is disabled after contract is upgraded.
    // @param _ticketId The id of the ticket to be bought.
    // @param _message  The purcharser of this ticket can display a message (e.g. and advertisement)
    //                  in the app for other users to read. The message maximum length is MAX_MESSAGE_LENGTH.
    function buyTicket(uint256 _ticketId, string _message) external payable notUpgraded {
        require(tickets[_ticketId].numBlocksExpiry != 0, "Invalid ticketId");
        require(!_exists(_ticketId), "Ticket was already sold");
        require(msg.value == tickets[_ticketId].sellingPrice, "Invalid ticket price");
        require(bytes(_message).length < MAX_MESSAGE_LENGTH, "Message is too long");

        tickets[_ticketId].expiryBlock = block.number.add(tickets[_ticketId].numBlocksExpiry);
        tickets[_ticketId].message = _message;
        _mint(msg.sender, _ticketId);
        cashEarnedSinceLastUpdate = cashEarnedSinceLastUpdate.add(msg.value);

        emit TicketBought(_ticketId, msg.sender, tickets[_ticketId].expiryBlock, _message);
    }

    // @dev Returns whether or not a ticket is valid. A valid becomes invalid if it was created and it
    //      has not expired yet.
    //      This function is disabled after contract is upgraded.
    // @param _ticketId The id of the ticket.
    // @return Whether or not a ticket is valid.
    function isTicketValid(uint256 _ticketId) external view notUpgraded returns (bool) {
        require(_exists(_ticketId), "Unknow ticketId");
        return block.number < tickets[_ticketId].expiryBlock;
    }

    // @dev Returns number of ether a token holder is eligible to withdraw.
    //      If the token distribution has been changed, the function updateTokenDistribution() needs to be called
    //      prior to this to reflect those changes.
    //      This function is disabled after contract is upgraded.
    // @param _tokenHolder The token holder address.
    // @return Number of ether.
    function getWithdrawableCash(address _tokenHolder) external view notUpgraded returns (uint256) {
        return withdrawableCash[_tokenHolder];
    }

    // @dev Withdraws the corresponding ether to the token holder calling this function.
    //      If the token distribution has been changed, the function updateTokenDistribution() needs to be called
    //      prior to this to reflect those changes.
    //      This function is disabled after contract is upgraded.
    function withdrawCash() external notUpgraded {
        require(!withdrawn[msg.sender]); // stop re-entrancy attack 
        withdrawn[msg.sender] = true;
        msg.sender.transfer(withdrawableCash[msg.sender]);
        withdrawableCash[msg.sender] = 0;
        emit CashWithdrawn(msg.sender);
    }

    // @dev Updates the token distribution and the withdrawable amounts for a correct earnings distribution.
    //      This function needs to be called before calling `withdrawCash()` and after the token distribution
    //      has been changed.
    //      This function is disabled after contract is upgraded.
    function updateTokenDistribution() external notUpgraded {
        uint256 tokenTotalSupply = token.totalSupply();
        address[] memory tokenHolders = token.holders();
        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address tokenHolder = tokenHolders[i];
            withdrawableCash[tokenHolder] = withdrawableCash[tokenHolder].add(
                cashEarnedSinceLastUpdate.mul(token.balanceOf(tokenHolder)).div(tokenTotalSupply)
            );
            withdrawn[tokenHolder] = false;
        }
        cashEarnedSinceLastUpdate = 0;
        emit TokenDistributionUpdated();
    }
}
