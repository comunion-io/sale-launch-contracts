import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs'
import { expect } from 'chai'
import { ethers } from 'hardhat'

describe('WESaleFactory', function () {
  const adminRoleBytes = ethers.utils.id('ADMIN_ROLE')
  const dexRouterSetterBytes = ethers.utils.id('DEX_ROUTER_SETTER_ROLE')
  const dexRouterBytes = ethers.utils.id('DEX_ROUTER')
  const WESaleBytes = ethers.utils.id('WESALES')

  const feeTo = '0xa6771e585E91C6ce7D1EeB578EDbe0696d37d962'
  const dexRouter = '0xa6771e585E91C6ce7D1EeB578EDbe0696d37d962'
  const startedAt = Math.floor(new Date().getTime() / 1000)
  let endedAt
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWESaleFactoryFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, founder] = await ethers.getSigners()
    const WESaleFactory = await ethers.getContractFactory('WESaleFactory')
    const wesaleFactory = await WESaleFactory.deploy(feeTo, owner.address)
    return { wesaleFactory, owner, founder }
  }

  describe('Deployment', function () {
    it('Should set the right feeTo', async function () {
      const { wesaleFactory } = await loadFixture(deployWESaleFactoryFixture)
      expect(await wesaleFactory.feeTo()).to.equal(feeTo)
    })

    it('Should set the right admin for role', async function () {
      const { wesaleFactory } = await loadFixture(deployWESaleFactoryFixture)

      expect(await wesaleFactory.getRoleAdmin(dexRouterSetterBytes)).to.equal(
        adminRoleBytes
      )
      expect(await wesaleFactory.getRoleAdmin(dexRouterBytes)).to.equal(
        dexRouterSetterBytes
      )
      expect(await wesaleFactory.getRoleAdmin(WESaleBytes)).to.equal(
        await wesaleFactory.DEFAULT_ADMIN_ROLE()
      )
    })

    it('Should set the right role', async function () {
      const { wesaleFactory, owner, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      expect(
        await wesaleFactory.hasRole(adminRoleBytes, owner.address)
      ).to.equal(true)

      expect(
        await wesaleFactory.hasRole(adminRoleBytes, founder.address)
      ).to.equal(false)
    })

    it('Should fail if the owner proceeds to revoke their admin role', async function () {
      const { wesaleFactory, owner } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await expect(
        wesaleFactory.renounceRole(adminRoleBytes, owner.address)
      ).to.be.revertedWithCustomError(wesaleFactory, 'IllegalOperation')
    })
  })

  describe('AccessRole', function () {
    it('Should setting role, add user to role', async function () {
      const { wesaleFactory, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await wesaleFactory.grantRole(dexRouterSetterBytes, founder.address)
      expect(
        await wesaleFactory.hasRole(dexRouterSetterBytes, founder.address)
      ).to.equal(true)
    })

    it('Should setting role, admin revoke user role', async function () {
      const { wesaleFactory, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await wesaleFactory.grantRole(dexRouterSetterBytes, founder.address)
      expect(
        await wesaleFactory.revokeRole(dexRouterSetterBytes, founder.address)
      ).not.to.be.reverted
    })

    it('Should setting role, user renounce role', async function () {
      const { wesaleFactory, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await wesaleFactory.grantRole(dexRouterSetterBytes, founder.address)
      expect(
        await wesaleFactory
          .connect(founder)
          .renounceRole(dexRouterSetterBytes, founder.address)
      ).not.to.be.reverted
    })

    it('Should setting the router role to the router', async function () {
      const { wesaleFactory, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await wesaleFactory.grantRole(dexRouterSetterBytes, founder.address)
      await expect(wesaleFactory.grantRole(dexRouterBytes, founder.address)).to
        .be.reverted
      await wesaleFactory.connect(founder).grantRole(dexRouterBytes, dexRouter)
      expect(await wesaleFactory.hasRole(dexRouterBytes, dexRouter)).to.equal(
        true
      )
    })
  })

  describe('SetFeeTo', function () {
    it('Should can setting new fee to', async function () {
      const { wesaleFactory, founder } = await loadFixture(
        deployWESaleFactoryFixture
      )
      await wesaleFactory.setFeeTo(founder.address)
      expect(await wesaleFactory.feeTo()).to.equal(founder.address)
    })
  })
})
