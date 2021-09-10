/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * truffleframework.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

// const HDWalletProvider = require('@truffle/hdwallet-provider');
// const infuraKey = "fj4jll3k.....";
//
// const fs = require('fs');
// const mnemonic = fs.readFileSync(".secret").toString().trim();

var HDWalletProvider = require("truffle-hdwallet-provider");
var privateKey = "";

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  plugins: ['truffle-plugin-verify'],
  api_keys: {etherscan: 'FD5UCJ1251Q7Q3XCC4KSJZT1TSMJDBWUMQ'},

  networks: {
    mainnet: {
      provider: function () {
        return new HDWalletProvider(privateKey, 'https://mainnet.infura.io/v3/f62c97f0c1824e4099d90856e551b798')
      },
      network_id: '1',
      gas: 4000000,
      gasPrice: 110000000000,
    },
    development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 8545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
    },

    advanced: {
      port: 8777,             // Custom port
      network_id: 1342,       // Custom network
      gas: 8500000,           // Gas sent with each transaction (default: ~6700000)
      gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
      // from: <address>,        // Account to send txs from (default: accounts[0])
      websockets: true        // Enable EventEmitter interface for web3 (default: false)
    },

    ropsten: {
      provider: () => new HDWalletProvider(privateKey, 'https://ropsten.infura.io/v3/d00f3846a5dc4e1991ad35cda94d9f62'),
      network_id: 3,       // Ropsten's id
      gas: 8000000,        // Ropsten has a lower block limit than mainnet
      gasPrice: 30000000000,
      confirmations: 2,    // # of confs to wait between deployments. (default: 0)
      // timeoutBlocks: 500,  // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    },

    kovan: {
      provider: () => new HDWalletProvider(privateKey, 'https://kovan.infura.io/v3/14f0131b40b54ec8bd9e0a162bbdc41f'),
      network_id: 42,       // Ropsten's id
      gas: 8000000,        // Ropsten has a lower block limit than mainnet
      gasPrice: 1000000000,
      // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
      // timeoutBlocks: 500,  // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    },

    rinkeby: {
      provider: () => new HDWalletProvider(privateKey, 'https://rinkeby.infura.io/v3/14f0131b40b54ec8bd9e0a162bbdc41f'),
      network_id: 4,       // Ropsten's id
      gas: 10000000,        // Ropsten has a lower block limit than mainnet
      gasPrice: 1000000000,
      // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
      // timeoutBlocks: 500,  // # of blocks before a deployment times out  (minimum/default: 50)
      skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    },

    heco_testnet: {
      provider: () => new HDWalletProvider(privateKey, 'https://http-testnet.huobichain.com'),
      network_id: 256,
      gas: 8000000,           // Gas sent with each transaction (default: ~6700000)
      gasPrice: 1000000000,  // 20 gwei (in wei) (default: 100 gwei)
      // skipDryRun: true
    },

    heco_mainnet: {
      provider: () => new HDWalletProvider(privateKey, 'https://http-mainnet.hecochain.com'),
      network_id: 128,
      // confirmations: 10,
      // timeoutBlocks: 200,
      // gas: 30000000,           // Gas sent with each transaction (default: ~6700000)
      // gasPrice: 100000000000,  // 20 gwei (in wei) (default: 100 gwei)
      // skipDryRun: true
    },

    bsc_testnet: {
      provider: () => new HDWalletProvider(privateKey, 'https://data-seed-prebsc-1-s1.binance.org:8545'),
      network_id: 97,
      gas: 30000000,           // Gas sent with each transaction (default: ~6700000)
      gasPrice: 10000000000,  // 20 gwei (in wei) (default: 100 gwei)
      // skipDryRun: true
    },

    bsc: {
      provider: () => new HDWalletProvider(privateKey, 'https://bsc-dataseed1.ninicoin.io/'),
      network_id: 56,
      // confirmations: 10,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 84300000,           // Gas sent with each transaction (default: ~6700000)
      gasPrice: 10000000000
    },
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.6.12",    // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 200
        },
        // evmVersion: "byzantium"
      }
    },
  },
};
