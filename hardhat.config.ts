import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.18',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    enabled: false,
  },

  networks: {
    // hardhat: {
    //   allowUnlimitedContractSize: true,
    //   forking: {
    //     url: 'https://rpc.ankr.com/eth',
    //   },
    // },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    goerli: {
      url: 'https://rpc.ankr.com/eth_goerli',
      accounts: [
        // 0xc71
        '73db539d43d10f1447bf11fe006fb0b532a8978d12b0e69749d2e9bc4b11b2dd',
      ],
    },
    avaxtestnet: {
      url: 'https://api.avax-test.network/ext/bc/C/rpc',
      accounts: [
        // 0xc71
        '73db539d43d10f1447bf11fe006fb0b532a8978d12b0e69749d2e9bc4b11b2dd',
      ],
    },
    rolluxtestnet: {
      url: 'https://rpc-tanenbaum.rollux.com',
      accounts: [
        // 0xc71
        '73db539d43d10f1447bf11fe006fb0b532a8978d12b0e69749d2e9bc4b11b2dd',
      ],
    },
    syscointestnet: {
      url: 'https://rpc.tanenbaum.io/',
      accounts: [
        // 0xc71
        '73db539d43d10f1447bf11fe006fb0b532a8978d12b0e69749d2e9bc4b11b2dd',
      ],
    },
    syscoin: {
      url: 'https://rpc.syscoin.org',
      accounts: [
        // 0xc71
        '73db539d43d10f1447bf11fe006fb0b532a8978d12b0e69749d2e9bc4b11b2dd',
      ],
    },
  },
}

export default config
