"use strict";

const WcToken = artifacts.require('./WcToken.sol');
const Cashier = artifacts.require("./Cashier.sol");
const TokencraticMultiSigWallet = artifacts.require("./TokencraticMultiSigWallet.sol");

const TICKET_PRICE = 1 * new web3.BigNumber('1e18');
const TICKET_NUM_BLOCKS_EXPIRY = 10;

contract('Integration', function (accounts) {
    const constructor = accounts[1];
    const other = accounts[2];
    const creators = accounts.slice(3, 7);

    let token;
    let cashier;
    let wallet;

    describe('tests', async function () {
        before(async function () {
            token = await WcToken.new({ from: constructor });
            wallet = await TokencraticMultiSigWallet.new(token.address, 50, { from: constructor });
            cashier = await Cashier.new(token.address, { from: constructor });
            await cashier.transferOwnership(wallet.address, { from: constructor });
        });

        it('assign tokens to creators', async function () {
            const totalSupply = await token.totalSupply();
            for (let i = 0; i < creators.length; i++) {
                await token.transfer(creators[i], totalSupply.times(1 / creators.length).toFixed(), { from: constructor });
            }

            assert.equal(await token.balanceOf(constructor), 0);
            assert.equal(
                new web3.BigNumber(await token.balanceOf(creators[0])).eq(totalSupply.times(1 / creators.length)),
                true
            );
        });

        it('DAO can issue new tickets', async function () {
            const cashierInstance = web3.eth.contract(cashier.abi).at(cashier.address);
            const issueTicketCall = cashierInstance.issueTicket.getData(TICKET_NUM_BLOCKS_EXPIRY, TICKET_PRICE);

            const transactionId = (await wallet.submitTransaction(cashier.address, 0, issueTicketCall, { from: other })).logs[0].args.transactionId;
            await wallet.confirmTransaction(transactionId, { from: creators[1] });
            await wallet.confirmTransaction(transactionId, { from: creators[2] });

            assert.equal(await cashier.numTickets.call(), 0);
            await wallet.executeTransaction(transactionId, { from: other });
            assert.equal(await cashier.numTickets.call(), 1);
        });


        it('DAO gets paid', async function () {
            await cashier.buyTicket(0, "", { value: TICKET_PRICE, from: other });
            await cashier.updateTokenDistribution({ from: other });

            assert.equal(await web3.eth.getBalance(cashier.address), TICKET_PRICE);
            for (let i = 0; i < creators.length; i++) {
                assert.equal(parseInt(await cashier.getWithdrawableCash(creators[i])), TICKET_PRICE / 4);
                const balanceBefore = await web3.eth.getBalance(creators[i]);
                await cashier.withdrawCash({ from: creators[i] });
                const balanceAfter = await web3.eth.getBalance(creators[i]);
                assert.equal(balanceAfter.gt(balanceBefore), true);
            }
            assert.equal(await web3.eth.getBalance(cashier.address), 0);
        });

        it('DAO can upgrade', async function () {
            const cashierNewVersion = await Cashier.new(wallet.address, { from: constructor });

            const cashierInstance = web3.eth.contract(cashier.abi).at(cashier.address);
            const upgradeCall = cashierInstance.upgrade.getData(cashierNewVersion.address);

            const transactionId = (await wallet.submitTransaction(cashier.address, 0, upgradeCall, { from: other })).logs[0].args.transactionId;
            await wallet.confirmTransaction(transactionId, { from: creators[1] });
            await wallet.confirmTransaction(transactionId, { from: creators[2] });

            assert.equal(await cashier.upgraded.call(), false);
            await wallet.executeTransaction(transactionId, { from: other });
            assert.equal(await cashier.upgraded.call(), true);
            assert.equal(await cashier.newContractAddress.call(), cashierNewVersion.address);
        });
    });
});
