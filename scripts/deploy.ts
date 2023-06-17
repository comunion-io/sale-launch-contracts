import { ethers } from 'hardhat'

async function main() {
  // avax uniswap v2 router
  // const routerAddress = '0x52B2031Ea4232b68b88e1577206dc388EFcE2E49'
  const routerAddress = '0x29f7Ad37EC018a9eA97D4b3fEebc573b5635fA84'

  // feeTod
  const feeTo = '0xa6771e585E91C6ce7D1EeB578EDbe0696d37d962'
  const [owner] = await ethers.getSigners()

  const WESaleFactory = await ethers.getContractFactory('WESaleFactory')
  const wesaleFactory = await WESaleFactory.deploy(feeTo, owner.address)
  await wesaleFactory.deployed()

  console.log(`WESale deployed to ${wesaleFactory.address}`)
  const dexRouterBytes = ethers.utils.id('DEX_ROUTER')
  const dexRouterSetterBytes = ethers.utils.id('DEX_ROUTER_SETTER_ROLE')
  wesaleFactory
    .grantRole(dexRouterSetterBytes, owner.address)
    .then(async () => {
      await wesaleFactory.grantRole(dexRouterBytes, routerAddress)
    })
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
