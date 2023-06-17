import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { ParametersStruct } from '../typechain-types/contracts/WESaleFactory'

describe('WESaleFactory', function () {
  const adminRoleBytes = ethers.utils.id('ADMIN_ROLE')
  const dexRouterSetterBytes = ethers.utils.id('DEX_ROUTER_SETTER_ROLE')
  const dexRouterBytes = ethers.utils.id('DEX_ROUTER')
  const WESaleBytes = ethers.utils.id('WESALES')

  //   const feeTo = '0xa6771e585E91C6ce7D1EeB578EDbe0696d37d962'
  const dexRouter = '0xf164fC0Ec4E93095b804a4795bBe1e041497b92a'
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWESaleFactoryFixture() {
    // Contracts are deployed using the first signer/account by default
    const [
      owner,
      founder,
      routerSetter,
      feeTo,
      teamWallet,
      investor1,
      investor2,
    ] = await ethers.getSigners()
    const WESaleFactory = await ethers.getContractFactory('WESaleFactory')
    const wesaleFactory = await WESaleFactory.deploy(
      feeTo.address,
      owner.address
    )
    await wesaleFactory.grantRole(dexRouterSetterBytes, routerSetter.address)
    return {
      wesaleFactory,
      owner,
      founder,
      routerSetter,
      feeTo,
      teamWallet,
      investor1,
      investor2,
    }
  }
  async function deployTestTokenFixture() {
    const TestERC20 = await ethers.getContractFactory('TestERC20')
    const tokenA = await TestERC20.deploy(
      'Test Coin A',
      'TCA',
      ethers.BigNumber.from(2).pow(255)
    )
    const tokenB = await TestERC20.deploy(
      'Test Coin B',
      'TCB',
      ethers.BigNumber.from(2).pow(255)
    )
    const tokenC = await TestERC20.deploy(
      'Test Coin C',
      'TCC',
      ethers.BigNumber.from(2).pow(255)
    )
    return { tokenA, tokenB, tokenC }
  }
  async function create5SWESaleFixture() {
    const {
      wesaleFactory,
      owner,
      founder,
      routerSetter,
      feeTo,
      teamWallet,
      investor1,
      investor2,
    } = await loadFixture(deployWESaleFactoryFixture)
    const { tokenA, tokenB, tokenC } = await loadFixture(deployTestTokenFixture)
    const startedAt = await time.latest()
    const endedAt = startedAt + 3
    const parameters: ParametersStruct = {
      price: ethers.BigNumber.from(1),
      liquidityRate: ethers.BigNumber.from(1),
      minInvest: ethers.BigNumber.from(1),
      maxInvest: ethers.BigNumber.from(1),
      softCap: ethers.BigNumber.from(1),
      hardCap: ethers.BigNumber.from(1),
      router: dexRouter,
      dexInitPrice: ethers.BigNumber.from(1),
      startedAt: ethers.BigNumber.from(startedAt),
      endedAt: ethers.BigNumber.from(endedAt),
      firstRelease: ethers.BigNumber.from(1),
      cycle: ethers.BigNumber.from(1),
      cycleRelease: ethers.BigNumber.from(1),
    }
    const tx = await wesaleFactory.createSale(
      teamWallet.address,
      tokenA.address,
      tokenB.address,
      parameters
    )
    console.log(tx)
    return {
      wesaleFactory,
      owner,
      founder,
      routerSetter,
      feeTo,
      teamWallet,
      investor1,
      investor2,
    }
  }

  describe('Deployment', function () {
    it('Should set the right feeTo', async function () {
      await loadFixture(create5SWESaleFixture)
    })
  })
})
