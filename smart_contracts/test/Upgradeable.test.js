"use strict";

import assertRevert from './utils/assertRevert';
const Upgradeable = artifacts.require("./Upgradeable.sol");

contract('Upgradeable', function (accounts) {

    const owner = accounts[1];
    const other = accounts[2];

    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
    const NEW_CONTRACT_ADDRESS = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const NEW_CONTRACT_ADDRESS_2 = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    let upgradeable;

    describe('tests', async function () {

        beforeEach(async function () {
            upgradeable = await Upgradeable.new({ from: owner });
        });

        it('can upgrade', async function () {
            assert.isFalse(await upgradeable.upgraded.call());

            await web3.eth.sendTransaction({ from: other, to: upgradeable.address, value: 1 })

            assert.equal(1, await web3.eth.getBalance(upgradeable.address).toNumber());

            await upgradeable.upgrade(NEW_CONTRACT_ADDRESS, { from: owner });

            // check ether has been transferred
            assert.equal(0, await web3.eth.getBalance(upgradeable.address).toNumber());
            assert.equal(1, await web3.eth.getBalance(NEW_CONTRACT_ADDRESS).toNumber());

            assert.isTrue(await upgradeable.upgraded.call());
        });

        it('cannot upgrade twice', async function () {
            await upgradeable.upgrade(NEW_CONTRACT_ADDRESS, { from: owner });
            await assertRevert(upgradeable.upgrade(NEW_CONTRACT_ADDRESS_2, { from: owner }));
        });

        it('only owner can upgrade', async function () {
            await assertRevert(upgradeable.upgrade(NEW_CONTRACT_ADDRESS, { from: other }));
        });

        it('cannot upgrade to address 0x0', async function () {
            await assertRevert(upgradeable.upgrade(ZERO_ADDRESS, { from: owner }));
        });

        it('cannot upgrade to its own address', async function () {
            await assertRevert(upgradeable.upgrade(upgradeable.address, { from: owner }));
        });

        it('can create cascade of upgrades', async function () {
            // this is for the app to navigate to last version of cashier contract

            let firstVersion = upgradeable
            let lastVersion = upgradeable;

            for (let i = 0; i < 10; i++) {
                let newVersion = await Upgradeable.new({ from: owner });
                await lastVersion.upgrade(newVersion.address, { from: owner });
                lastVersion = newVersion;
            }

            let currentVersion = firstVersion;
            while (await currentVersion.upgraded.call())
                currentVersion = Upgradeable.at(await currentVersion.newContractAddress.call());

            assert.equal(currentVersion.address, lastVersion.address);
        });
    });
});
