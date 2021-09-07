let factory = artifacts.require("./CoinSwapV1Factory.sol");
let router = artifacts.require("./CoinSwapV1Router02.sol");
let oracle = artifacts.require("./Oracle.sol");
let inviteManager = artifacts.require("./InviteManager.sol");
let feeManager = artifacts.require("./FeeManager.sol");
let vester = artifacts.require("./FundAndTeamVester.sol");

let pool = artifacts.require("./Pool.sol");
let minting = artifacts.require("./SwapMining.sol");
let coins = artifacts.require("./CoinsToken.sol");
let NodeAuction = artifacts.require("./NodeAuction.sol");

let feeToSetter = "0x0444C019C90402033fF8246BCeA440CeB9468C88";
let wht = "0x55dD52297B998b33fe5959AeaC718C87b504b98e";
let mdxPerBlock = "1000000000000000000";
let startBlock = 7291609;
let targetToken = "0x9550984f32d30ac07Eda2CE097213aA868D32fe9";

module.exports = async function (deployer) {
  await deployer.deploy(factory, feeToSetter);
  await deployer.deploy(router, factory.address, wht);
  // await deployer.deploy(coins);
  await deployer.deploy(oracle, factory.address,"0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", targetToken);
  await deployer.deploy(feeManager, "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", feeToSetter);
  await deployer.deploy(inviteManager);
  await deployer.deploy(NodeAuction,"0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09",inviteManager.address);
  await deployer.deploy(vester, "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", feeToSetter, mdxPerBlock, startBlock);
  await deployer.deploy(pool, "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09", oracle.address, mdxPerBlock, startBlock);
  await deployer.deploy(
      minting,
      "0xf48c1D09A6793c65fD1b6c78c71cc62C08A86A09",
      factory.address,
      oracle.address,
      router.address,
      targetToken,
      mdxPerBlock,
      startBlock);

  const router1 = await router.deployed();
  router1.setSwapMining(minting.address);
  router1.setFeeManager(feeManager.address);

  const manager = await feeManager.deployed();
  manager.setRouter(router.address);
  manager.setFactory(factory.address);
  manager.setInviteManager(inviteManager.address);

  // const token = await coins.deployed();
  // token.addMinter(pool.address);
  // token.addMinter(minting.address);

  const poolContract = await pool.deployed();
  poolContract.setInviteManager(inviteManager.address);
};
