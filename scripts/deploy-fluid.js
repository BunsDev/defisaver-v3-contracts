/* eslint-disable import/no-extraneous-dependencies */

const hre = require('hardhat');
const { start } = require('./utils/starter');
const {
    redeploy, addrs, network, getOwnerAddr,
} = require('../test/utils');
const { topUp } = require('./utils/fork');
const { deployFluidT1RepayBundle, deployFluidT1BoostBundle } = require('../test/utils-fluid');

async function main() {
    const isFork = true;
    const senderAcc = (await hre.ethers.getSigners())[0];
    console.log(getOwnerAddr());
    if (isFork) {
        await topUp(senderAcc.address);
        await topUp(getOwnerAddr());
    }

    const fluidT1Open = await redeploy('FluidVaultT1Open', addrs[network].REGISTRY_ADDR, isFork);
    const fluidT1Supply = await redeploy('FluidVaultT1Supply', addrs[network].REGISTRY_ADDR, isFork);
    const fluidT1Withdraw = await redeploy('FluidVaultT1Withdraw', addrs[network].REGISTRY_ADDR, isFork);
    const fluidT1Borrow = await redeploy('FluidVaultT1Borrow', addrs[network].REGISTRY_ADDR, isFork);
    const fluidT1Payback = await redeploy('FluidVaultT1Payback', addrs[network].REGISTRY_ADDR, isFork);
    const fluidT1Adjust = await redeploy('FluidVaultT1Adjust', addrs[network].REGISTRY_ADDR, isFork);
    const fluidRatioTrigger = await redeploy('FluidRatioTrigger', addrs[network].REGISTRY_ADDR, isFork);
    const fluidRatioChecker = await redeploy('FluidRatioCheck', addrs[network].REGISTRY_ADDR, isFork);
    const view = await redeploy('FluidView', addrs[network].REGISTRY_ADDR, isFork);

    console.log(`FluidVaultT1Open: ${fluidT1Open.address}`);
    console.log(`FluidVaultT1Supply: ${fluidT1Supply.address}`);
    console.log(`FluidVaultT1Withdraw: ${fluidT1Withdraw.address}`);
    console.log(`FluidVaultT1Borrow: ${fluidT1Borrow.address}`);
    console.log(`FluidVaultT1Payback: ${fluidT1Payback.address}`);
    console.log(`FluidVaultT1Adjust: ${fluidT1Adjust.address}`);
    console.log(`FluidRatioTrigger: ${fluidRatioTrigger.address}`);
    console.log(`FluidRatioCheck: ${fluidRatioChecker.address}`);
    console.log(`FluidView: ${view.address}`);

    /* //////////////////////////////////////////////////////////////
                            AUTOMATION
    ////////////////////////////////////////////////////////////// */
    const repayBundleId = await deployFluidT1RepayBundle(senderAcc, isFork);
    const boostBundleId = await deployFluidT1BoostBundle(senderAcc, isFork);

    console.log(`Repay bundle id: ${repayBundleId}`);
    console.log(`Boost bundle id: ${boostBundleId}`);

    process.exit(0);
}

start(main);
