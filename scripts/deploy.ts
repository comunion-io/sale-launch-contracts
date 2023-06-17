import { ethers } from 'hardhat'

async function main() {
  const WESale = await ethers.getContractFactory('WESale')
  const wesale = await WESale.deploy()
  await wesale.deployed()

  console.log(`WESale deployed to ${wesale.address}`)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
