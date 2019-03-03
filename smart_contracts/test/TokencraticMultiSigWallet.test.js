"use strict";

import assertRevert from './utils/assertRevert';

const TokencraticMultiSigWallet = artifacts.require("./TokencraticMultiSigWallet.sol");
const WcToken = artifacts.require('./WcToken.sol');

contract('TokencraticMultiSigWallet', function (accounts) {
    const users = accounts.slice(1, 6);
    const other = accounts[6];

    let token;
    let wallet;

    describe('constructor', async function () {
        beforeEach(async function () {
            token = await WcToken.new({ from: other });
            wallet = await TokencraticMultiSigWallet.new(token.address, 50, { from: other });

            const totalSupply = await token.totalSupply();
            await token.transfer(users[0], totalSupply.times(0.2).toFixed(), { from: other });
            await token.transfer(users[1], totalSupply.times(0.2).toFixed(), { from: other });
            await token.transfer(users[2], totalSupply.times(0.5).toFixed(), { from: other });
            await token.transfer(users[3], totalSupply.times(0.099999).toFixed(), { from: other });
            await token.transfer(users[4], totalSupply.times(0.000001).toFixed(), { from: other });
        });

        it('voting-based transaction execution works', async function () {
            await web3.eth.sendTransaction({ from: other, to: wallet.address, value: 1 });
            await wallet.submitTransaction(other, 1, "", { from: other });

            await wallet.confirmTransaction(0, { from: users[0] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);

            await wallet.confirmTransaction(0, { from: users[1] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);

            await wallet.confirmTransaction(0, { from: users[2] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), true);

            const balanceBefore = await web3.eth.getBalance(other);
            await wallet.executeTransaction(0, { from: users[3] });
            const balanceAfter = await web3.eth.getBalance(other);

            assert.equal(balanceAfter.gt(balanceBefore), true);
        });

        it('rejects votes from address which does not hold enough tokens to vote', async function() {
            // Now ensure that this user is not allowed to vote
            await web3.eth.sendTransaction({ from: other, to: wallet.address, value: 1 });
            await wallet.submitTransaction(other, 1, "", { from: other });

            // Address #0 is allowed to vote, as they own 20% of the total token supply
            await wallet.confirmTransaction(0, { from: users[0] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);

            // Address #4 is *not* allowed to vote, as they own 0.0001% of the total token supply
            await assertRevert(wallet.confirmTransaction(0, { from: users[4] }));
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);
        });

        it('isConfirmed remains false after vote from address which does not hold enough tokens to vote', async function() {
            // Now ensure that this user is not allowed to vote
            await web3.eth.sendTransaction({ from: other, to: wallet.address, value: 1 });
            await wallet.submitTransaction(other, 1, "", { from: other });

            // Vote from Addresses #0, #1, #3, & #4
            const voteIndices = [0, 1, 3, 4];
            for (let i = 0; i < voteIndices.length; ++i) {
                const address = users[voteIndices[i]];
                try {
                    await wallet.confirmTransaction(0, { from: address });
                } catch (ex) {
                    // do nothing
                }
            }

            // Even though we know that they add up to exactly 50%, the transaction should still
            // *not* be confirmed, as address #4 vote would have been rejected as it does not hold
            // enough tokens to vote.
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);
        });

        it('cannot execute transaction if threshold is not reached', async function () {
            await web3.eth.sendTransaction({ from: other, to: wallet.address, value: 1 });
            await wallet.submitTransaction(other, 1, "", { from: other });

            await wallet.confirmTransaction(0, { from: users[0] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);
            await assertRevert(wallet.executeTransaction(0, { from: users[3] }));
        });

        it('change threshold', async function () {
            await web3.eth.sendTransaction({ from: other, to: wallet.address, value: 1 });
            await wallet.submitTransaction(other, 1, "", { from: other });

            await wallet.confirmTransaction(0, { from: users[0] });
            await wallet.confirmTransaction(0, { from: users[1] });
            await wallet.confirmTransaction(0, { from: users[2] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), true);

            const walletInstance = web3.eth.contract(wallet.abi).at(wallet.address);
            const setThresholdCall = walletInstance.setThreshold.getData(99);
            await wallet.submitTransaction(wallet.address, 0, setThresholdCall, { from: other });

            await wallet.confirmTransaction(1, { from: users[0] });
            await wallet.confirmTransaction(1, { from: users[1] });
            await wallet.confirmTransaction(1, { from: users[2] });
            assert.equal(await wallet.threshold.call(), 50);
            await wallet.executeTransaction(1, { from: users[3] });
            assert.equal(await wallet.threshold.call(), 99);
            assert.equal(await wallet.isConfirmed(0, { from: other }), false);

            await wallet.confirmTransaction(0, { from: users[3] });
            assert.equal(await wallet.isConfirmed(0, { from: other }), true);

            const balanceBefore = await web3.eth.getBalance(other);
            await wallet.executeTransaction(0, { from: users[3] });
            const balanceAfter = await web3.eth.getBalance(other);

            assert.equal(balanceAfter.gt(balanceBefore), true);
        });

        it('addresses different from wallet itself cannot change the threshold', async function () {
            await assertRevert(wallet.setThreshold(60, { from: other }));
        });
    });
});
