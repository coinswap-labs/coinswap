let factory = artifacts.require("./CoinSwapV1Factory.sol");
let router = artifacts.require("./CoinSwapV1Router02.sol");
let oracle = artifacts.require("./Oracle.sol");
let inviteManager = artifacts.require("./InviteManager.sol");
let feeManager = artifacts.require("./FeeManager.sol");
let vester = artifacts.require("./FundAndTeamVester.sol");
let migrator = artifacts.require("./Migrator.sol");

let pool = artifacts.require("./Pool.sol");
let minting = artifacts.require("./SwapMining.sol");
let coins = artifacts.require("./CoinsToken.sol");
let NodeAuction = artifacts.require("./NodeAuction.sol");

let feeToSetter = "0xecc38Bc7c47786bAe8f2d40240Cc65f9A8cB3b6B";
let defaultFeeAddress = '0x6eC88D51328721Edc94f1Ad6b8830Bd841aA6135';
let wht = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
// let mdxPerBlock = "1000000000000000000";
// let startBlock = 7291609;
let targetToken = "0x55d398326f99059ff775485246999027b3197955";

let pancakeRouter = "0x10ed43c718714eb63d5aa57b78b54704e256024e";
let pancakeFactory = "0xca143ce32fe78f1f7019d7d551a6402fc5350c73";

let mdexRouter = "0x7dae51bd3e3376b8c7c4900e9107f12be3af1ba8";
let mdexFactory = "0x3cd1c46068daea5ebb0d3f55f6915b10648062b8";

let biswapRouter = "0x3a6d8ca21d1cf76f653a67577fa0d27453350dd8";
let biswapFactory = "0x858e3312ed3a876947ea49d572a7c42de08af7ee";

let apeSwapRouter = "0xcf0febd3f17cef5b47b0cd257acf6025c5bff3b7";
let apeSwapFactory = "0x0841bd0b734e4f5853f0dd8d7ea041c241fb0da6";

let bakerySwapRouter = "0xCDe540d7eAFE93aC5fE6233Bee57E1270D3E330F";
let bakerySwapFactory = "0x01bf7c66c6bd861915cdaae475042d3c4bae16a7";

let BabySwapRouter = "0x325e343f1de602396e256b67efd1f61c3a6b38bd";
let BabySwapFactory = "0x86407bea2078ea5f5eb5a52b2caa963bc1f889da ";

module.exports = async function (deployer) {
    // await deployer.deploy(factory, feeToSetter);
    // await deployer.deploy(router, "0xF964B1b0C64ccFb0854E77Fd2DbEd68D0aADd26c", wht);
    // await deployer.deploy(coins);
    // await deployer.deploy(oracle, "0xF964B1b0C64ccFb0854E77Fd2DbEd68D0aADd26c", coins.address, targetToken);
    // await deployer.deploy(feeManager, coins.address, defaultFeeAddress);
    // await deployer.deploy(inviteManager);
    // await deployer.deploy(NodeAuction, coins.address, inviteManager.address);
    await deployer.deploy(migrator, mdexRouter, "0x6022Ff1654247f4e715254be00daa49f163b8D00", mdexFactory, "0xF964B1b0C64ccFb0854E77Fd2DbEd68D0aADd26c");
    // await deployer.deploy(vester, "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", feeToSetter, mdxPerBlock, startBlock);
    // await deployer.deploy(pool, "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", oracle.address, mdxPerBlock, startBlock);
    // await deployer.deploy(
    //     minting,
    //     "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09",
    //     factory.address,
    //     oracle.address,
    //     router.address,
    //     targetToken,
    //     mdxPerBlock,
    //     startBlock);
    //
    // const router1 = await router.deployed();
    // router1.setSwapMining(minting.address);
    // router1.setFeeManager(feeManager.address);
    //
    // const manager = await feeManager.deployed();
    // manager.setRouter(router.address);
    // manager.setFactory(factory.address);
    // manager.setInviteManager(inviteManager.address);

    // const token = await coins.deployed();
    // token.addMinter(pool.address);
    // token.addMinter(minting.address);

    // const poolContract = await pool.deployed();
    // poolContract.setInviteManager(inviteManager.address);
};
