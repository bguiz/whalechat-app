"use strict";

import assertRevert from './utils/assertRevert';
import increaseBlocks from './utils/increaseBlocks';

const WcToken = artifacts.require('./WcToken.sol');
const Cashier = artifacts.require("./Cashier.sol");

const TICKET_PRICE = 1 * new web3.BigNumber('1e18');
const TICKET_NUM_BLOCKS_EXPIRY = 100;
const TICKET_DATA = 'Best crypto otc deals: some-website.com'

contract('cashier', function (accounts) {
    const owner = accounts[1];
    const users = accounts.slice(2, 4);
    const other = accounts[4];
    const other2 = accounts[5];

    let token;
    let cashier;
    let totalSupply;
    let ticketExpiryBlock;

    async function issueAndBuyTicket() {
        const ticketId = (await cashier.issueTicket(TICKET_NUM_BLOCKS_EXPIRY, TICKET_PRICE, { from: owner }))
            .logs[0].args.ticketId;
        await cashier.buyTicket(ticketId, TICKET_DATA, { value: TICKET_PRICE, from: other });
        return ticketId;
    }

    async function withdraw() {
        for (let i = 0; i < users.length; i++) {
            const balanceBefore = await web3.eth.getBalance(users[i]);
            await cashier.withdrawCash({ from: users[i] });
            const balanceAfter = await web3.eth.getBalance(users[i]);
            assert.equal(balanceAfter.gt(balanceBefore), true);
        }
    }

    describe('all tests', async function () {
        beforeEach(async function () {
            token = await WcToken.new({ from: other });
            cashier = await Cashier.new(token.address, { from: owner });
            totalSupply = await token.totalSupply();
        });

        it('only owner can issue tickets', async function () {
            await assertRevert(cashier.issueTicket(TICKET_NUM_BLOCKS_EXPIRY, TICKET_PRICE, { from: other }));
        });

        it('ticket expiry cannot be zero', async function () {
            await assertRevert(cashier.issueTicket(0, TICKET_PRICE, { from: owner }));
        });

        it('ticket price cannot be zero', async function () {
            await assertRevert(cashier.issueTicket(TICKET_NUM_BLOCKS_EXPIRY, 0, { from: owner }));
        });

        it('ticket message cannot be too long', async function () {
            const ticketData = 'a'.repeat(1 + parseInt(await cashier.MAX_MESSAGE_LENGTH.call()));
            const ticketId = (await cashier.issueTicket(TICKET_NUM_BLOCKS_EXPIRY, TICKET_PRICE, { from: owner }))
                .logs[0].args.ticketId;
            await assertRevert(cashier.buyTicket(ticketId, ticketData, { value: TICKET_PRICE, from: other }));
        });

        describe('more tests', async function () {
            beforeEach(async function () {
                const ticketId = await issueAndBuyTicket();
                ticketExpiryBlock = TICKET_NUM_BLOCKS_EXPIRY + web3.eth.blockNumber;
                assert.equal(await cashier.ownerOf(ticketId), other);

                await token.transfer(users[0], totalSupply.times(0.6).toFixed(), { from: other });
                await token.transfer(users[1], totalSupply.times(0.4).toFixed(), { from: other });
            });

            it('token holders can withdraw earnings', async function () {
                await cashier.updateTokenDistribution({ from: other });

                assert.equal(await web3.eth.getBalance(cashier.address), TICKET_PRICE);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), TICKET_PRICE * 0.6);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), TICKET_PRICE * 0.4);

                await withdraw();
                assert.equal(await web3.eth.getBalance(cashier.address), 0);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), 0);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), 0);
            });


            it('updating token distribution before withdrawing earnings', async function () {
                assert.equal(await web3.eth.getBalance(cashier.address), TICKET_PRICE);
                await cashier.updateTokenDistribution({ from: other });
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), TICKET_PRICE * 0.6);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), TICKET_PRICE * 0.4);

                token.transfer(users[1], totalSupply.times(0.2).toFixed(), { from: users[0] });

                await issueAndBuyTicket();
                assert.equal(await web3.eth.getBalance(cashier.address), 2 * TICKET_PRICE);
                await cashier.updateTokenDistribution({ from: other });
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), TICKET_PRICE);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), TICKET_PRICE);

                await withdraw();
                assert.equal(await web3.eth.getBalance(cashier.address), 0);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), 0);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), 0);
            });

            it('*not* updating token distribution before withdrawing earnings', async function () {
                token.transfer(users[1], totalSupply.times(0.2).toFixed(), { from: users[0] });

                await issueAndBuyTicket();
                assert.equal(await web3.eth.getBalance(cashier.address), 2 * TICKET_PRICE);
                await cashier.updateTokenDistribution({ from: other });
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[0])), 2 * TICKET_PRICE * 0.4);
                assert.equal(parseInt(await cashier.getWithdrawableCash(users[1])), 2 * TICKET_PRICE * 0.6);
            });

            it('ticket becomes invalid after expiry', async function () {
                assert.equal(await cashier.isTicketValid(0), true);
                const numBlocksToIncrease = ticketExpiryBlock - web3.eth.blockNumber;
                await increaseBlocks(numBlocksToIncrease);
                assert.equal(await cashier.isTicketValid(0), false);
            });

            it('cannot buy the same ticket twice', async function () {
                await assertRevert(cashier.buyTicket(0, TICKET_DATA, { value: TICKET_PRICE, from: users[0] }));
            });

            it('can transfer ticket', async function () {
                assert.equal(await cashier.ownerOf(0), other);
                await cashier.safeTransferFrom(other, other2, 0, { from: other });
                assert.equal(await cashier.ownerOf(0), other2);
            });
        });

        describe('upgrade', async function () {
            it('cannot issue/buy tickets, check withdrawable cash, withdraw cash or update token distribution', async function () {
                const cashier2 = await Cashier.new(token.address, { from: owner });
                const ticketId = (await cashier.issueTicket(TICKET_NUM_BLOCKS_EXPIRY, TICKET_PRICE, { from: owner }))
                    .logs[0].args.ticketId;
                await cashier.upgrade(cashier2.address, { from: owner });

                await assertRevert(cashier.issueTicket(5, TICKET_PRICE, { from: other }));
                await assertRevert(cashier.buyTicket(ticketId, TICKET_DATA, { value: TICKET_PRICE, from: other }));
                await assertRevert(cashier.getWithdrawableCash(users[0]));
                await assertRevert(cashier.withdrawCash({ from: users[0] }));
                await assertRevert(cashier.updateTokenDistribution({ from: other }));
            });
        });
    });
});

