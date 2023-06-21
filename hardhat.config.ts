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
      //   viaIR: true,
    },
  },
  gasReporter: {
    enabled: false,
  },

  networks: {
    hardhat: {
      //   allowUnlimitedContractSize: true,
      //   forking: {
      //     url: 'https://rpc.ankr.com/eth',
      //   },
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    goerli: {
      url: 'https://rpc.ankr.com/eth_goerli',
    },
    avaxtestnet: {
      url: 'https://api.avax-test.network/ext/bc/C/rpc',
    },
    rolluxtestnet: {
      url: 'https://rpc-tanenbaum.rollux.com',
    },
    syscointestnet: {
      url: 'https://rpc.tanenbaum.io/',
    },
    syscoin: {
      url: 'https://rpc.syscoin.org',
    },
  },
}

export default config
