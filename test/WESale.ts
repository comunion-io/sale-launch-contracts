import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { ethers } from 'hardhat'
import { ParametersStruct } from '../typechain-types/contracts/WESaleFactory'
import { WESale } from '../typechain-types'

describe('WESaleFactory', function () {
  const adminRoleBytes = ethers.utils.id('ADMIN_ROLE')
  const dexRouterSetterBytes = ethers.utils.id('DEX_ROUTER_SETTER_ROLE')
  const dexRouterBytes = ethers.utils.id('DEX_ROUTER')
  const WESaleBytes = ethers.utils.id('WESALES')
  console.log('dexRouterSetterBytes', dexRouterSetterBytes)
  console.log('dexRouterBytes', dexRouterBytes)
  console.log('WESaleBytes', WESaleBytes)
  //   const feeTo = '0xa6771e585E91C6ce7D1EeB578EDbe0696d37d962'
  const dexRouter = '0x29f7Ad37EC018a9eA97D4b3fEebc573b5635fA84'
  console.log(
    ethers.utils.id(
      'WESaleCreated(address,address,(uint256,uint24,uint256,uint256,uint256,uint256,address,uint256,uint256,uint256,uint24,uint24,uint24,uint24))'
    )
  )
  //   total presale token
  const presaleSupply = '21000000'
  const investorInitBalance = '10000'
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWESaleFactoryFixture() {
    // Contracts are deployed using the first signer/account by default
    const [
      owner,
      founder,
      routerSetter,
      //   feeTo,
      //   teamWallet,
      //   investor1,
      investor2,
    ] = await ethers.getSigners()
    const feeTo = owner
    const teamWallet = founder
    const investor1 = routerSetter
    const WESaleFactory = await ethers.getContractFactory('WESaleFactory')
    const wesaleFactory = await WESaleFactory.deploy(
      feeTo.address,
      owner.address
    )
    await wesaleFactory.grantRole(dexRouterSetterBytes, routerSetter.address)
    await wesaleFactory
      .connect(routerSetter)
      .grantRole(dexRouterBytes, dexRouter)
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
    const investTokenA = await TestERC20.deploy(
      'Test Coin A',
      'TCA',
      18,
      ethers.BigNumber.from(2).pow(255)
    )
    const investTokenB = await TestERC20.deploy(
      'Test Coin B',
      'TCB',
      8,
      ethers.BigNumber.from(2).pow(255)
    )
    const presaleToken = await TestERC20.deploy(
      'Test Coin C',
      'TCC',
      6,
      ethers.BigNumber.from(2).pow(255)
    )
    return { investTokenA, investTokenB, presaleToken }
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
    const { investTokenA, investTokenB, presaleToken } = await loadFixture(
      deployTestTokenFixture
    )
    const presaleTokenDecimals = await presaleToken.decimals()
    const investTokenADecimals = await investTokenA.decimals()
    const investTokenBDecimals = await investTokenB.decimals()
    await presaleToken.transfer(
      founder.address,
      ethers.utils.parseUnits(presaleSupply, presaleTokenDecimals)
    )
    const initBalanceA = ethers.utils.parseUnits(
      investorInitBalance,
      investTokenADecimals
    )
    const initBalanceB = ethers.utils.parseUnits(
      investorInitBalance,
      investTokenBDecimals
    )
    await investTokenA.transfer(investor1.address, initBalanceA)
    await investTokenA.transfer(investor2.address, initBalanceA)
    await investTokenB.transfer(investor1.address, initBalanceB)
    await investTokenB.transfer(investor2.address, initBalanceB)
    const startedAt = await time.latest()
    const endedAt = startedAt + 5
    const presalePerPrice = ethers.utils.parseUnits('10', presaleTokenDecimals)
    const presalePerDexInitPrice = ethers.utils.parseUnits(
      '20',
      presaleTokenDecimals
    )
    const sortCap = ethers.utils.parseUnits('200', investTokenADecimals)
    const hardCap = ethers.utils.parseUnits('1000', investTokenADecimals)
    const minInvest = ethers.utils.parseUnits('1', investTokenADecimals)
    const maxInvest = ethers.utils.parseUnits('1000', investTokenADecimals)
    const liquidityRate = ethers.BigNumber.from(700000)
    const firstRelease = ethers.BigNumber.from(300000)
    const cycle = ethers.BigNumber.from(60)
    const cycleRelease = ethers.BigNumber.from(200000)
    const parameters: ParametersStruct = {
      price: presalePerPrice,
      liquidityRate: liquidityRate,
      minInvest: minInvest,
      maxInvest: maxInvest,
      softCap: sortCap,
      hardCap: hardCap,
      router: dexRouter,
      dexInitPrice: presalePerDexInitPrice,
      startedAt: ethers.BigNumber.from(startedAt),
      endedAt: ethers.BigNumber.from(endedAt),
      firstRelease: firstRelease,
      cycle: cycle,
      cycleRelease: cycleRelease,
      investTokenDecimals: ethers.BigNumber.from(0),
    }
    const allowPresaleTokenAmount = presalePerPrice
      .mul(hardCap)
      .div(ethers.utils.parseUnits('1', investTokenADecimals))
      .add(
        hardCap
          .mul(liquidityRate)
          .mul(presalePerDexInitPrice)
          .div(1000000)
          .div(ethers.utils.parseUnits('1', investTokenADecimals))
      )
    await presaleToken
      .connect(founder)
      .approve(wesaleFactory.address, allowPresaleTokenAmount)
    const tx = await wesaleFactory
      .connect(founder)
      .createSale(
        teamWallet.address,
        presaleToken.address,
        investTokenA.address,
        parameters
      )

    let transactionReceipt = await ethers.provider.getTransactionReceipt(
      tx.hash
    )
    let weSale
    for (let log of transactionReceipt.logs) {
      if (log.address == wesaleFactory.address) {
        try {
          let result = wesaleFactory.interface.decodeEventLog(
            'WESaleCreated',
            log.data,
            log.topics
          )
          let wesaleAddress = result['_wesale']
          weSale = await ethers.getContractAt('WESale', wesaleAddress)
          if (weSale) {
            break
          }
        } catch {
          //   console.log('wesaleFactory.interface.decodeEventLog error: ', log)
        }
      }
    }
    return {
      wesaleFactory,
      owner,
      founder,
      routerSetter,
      feeTo,
      teamWallet,
      investor1,
      investor2,
      weSale,
      parameters,
      investTokenA,
      investTokenB,
      presaleToken,
    }
  }

  describe('WESale', function () {
    it('Should create wesale', async function () {
      const { weSale, parameters } = await loadFixture(create5SWESaleFixture)
      if (weSale) {
        const _parameters = await weSale.parameters()
        expect(_parameters.dexInitPrice).to.equal(parameters.dexInitPrice)
      }
    })

    it('Should founder can devest', async function () {
      const { weSale, presaleToken, founder } = await loadFixture(
        create5SWESaleFixture
      )
      if (weSale) {
        await expect(weSale.founderDivest()).to.be.revertedWith(
          'Ownable: caller is not the owner'
        )
        await expect(
          weSale.connect(founder).founderDivest()
        ).to.be.revertedWithCustomError(
          weSale,
          'DidNotMeetDivestmentRequirements'
        )
        await sleep(1000)
        expect(await weSale.connect(founder).founderDivest()).not.to.be.throw
        expect(await presaleToken.balanceOf(founder.address)).to.equal(
          ethers.utils.parseUnits(presaleSupply, await presaleToken.decimals())
        )
      }
    })

    it('Should invest', async function () {
      const {
        weSale,
        investTokenA,
        founder,
        parameters,
        teamWallet,
        investor1,
        owner,
      } = await loadFixture(create5SWESaleFixture)
      if (weSale) {
        const investTokenADecimals = await investTokenA.decimals()
        const investTokenAConnectInvestor1 = await investTokenA.connect(
          investor1
        )
        const weSaleConnectInvestor1 = await weSale.connect(investor1)
        const investAmount = ethers.utils.parseUnits(
          '1000',
          investTokenADecimals
        )

        await investTokenAConnectInvestor1.approve(weSale.address, investAmount)
        expect(await weSaleConnectInvestor1.invest(investAmount)).not.to.throw

        expect(await weSale.getInvestOf(investor1.address)).to.equal(
          investAmount
        )
        describe('Invested', function () {
          it('Should founder transfer', async function () {
            const weSaleConnnectFounder = weSale.connect(founder)
            const result =
              await weSaleConnnectFounder.getTransferLiquidityInvestAmount()
            const amountA = result._investTransferLPAmount
              .mul(await parameters.dexInitPrice)
              .div(ethers.BigNumber.from(10).pow(investTokenADecimals))
            // weSale.connect(founder).transferLiquidity()
            const deadline = Math.floor(new Date().getTime() / 1000) + 3600
            let router = await ethers.getContractAt(
              'IUniswapV2Router02',
              dexRouter
            )
            let data = router.interface.encodeFunctionData('addLiquiditySYS', [
              investTokenA.address,
              amountA,
              0,
              0,
              teamWallet.address,
              deadline,
            ])
            // console.log('LPData: ', data)
            const message = {
              domain: {
                name: 'WESale',
                version: '0.0.1',
                chainId: 57000,
                verifyingContract: '0x610ccf9d23AF31C73B762Be77166e4AB51684C2b',
              },
              types: {
                TransferLiquidity: [
                  { name: '_router', type: 'address' },
                  { name: '_amountA', type: 'uint256' },
                  { name: '_data', type: 'bytes' },
                ],
              },
              data: {
                _router: dexRouter,
                _amountA: amountA,
                _data: data,
              },
            }
            const sign = await owner._signTypedData(
              message.domain,
              message.types,
              message.data
            )
            let tx = await weSaleConnnectFounder.transferLiquidity(
              amountA,
              data,
              sign
            )
            // console.log(tx)
          })
        })
      }
    })

    // it('Should be equal to the investment amountt', async function () {
    //   const { weSale, investTokenA, investor1 } = await loadFixture(
    //     create5SWESaleFixture
    //   )
    //   if (weSale) {
    //     const investTokenADecimals = await investTokenA.decimals()
    //     const investTokenAConnectInvestor1 = await investTokenA.connect(
    //       investor1
    //     )
    //     const weSaleConnectInvestor1 = await weSale.connect(investor1)
    //     const investAmount = ethers.utils.parseUnits(
    //       '1000',
    //       investTokenADecimals
    //     )

    //     await investTokenAConnectInvestor1.approve(weSale.address, investAmount)
    //     expect(await weSaleConnectInvestor1.invest(investAmount)).not.to.throw

    //     expect(await weSale.getInvestOf(investor1.address)).to.equal(
    //       investAmount
    //     )

    //     describe('Invested', function () {
    //       it('Should be equal to the additional investment amount', async function () {
    //         // additional 10
    //         const additionalInvestAmount = ethers.utils.parseUnits(
    //           '10',
    //           investTokenADecimals
    //         )
    //         await investTokenAConnectInvestor1.approve(
    //           weSale.address,
    //           additionalInvestAmount
    //         )
    //         expect(await weSaleConnectInvestor1.invest(additionalInvestAmount))
    //           .not.to.throw

    //         expect(await weSale.getInvestOf(investor1.address)).to.equal(
    //           investAmount.add(additionalInvestAmount)
    //         )
    //       })

    //       it('Should investor can deinvest', async function () {
    //         expect(await weSale.connect(investor1).divest()).not.to.be.throw
    //         expect(
    //           await investTokenAConnectInvestor1.balanceOf(investor1.address)
    //         ).to.equal(
    //           ethers.utils.parseUnits(investorInitBalance, investTokenADecimals)
    //         )
    //       })

    //       it('Should be over, and no further investment can be made', async function () {
    //         // additional 10
    //         const additionalInvestAmount = ethers.utils.parseUnits(
    //           '200',
    //           investTokenADecimals
    //         )
    //         await investTokenAConnectInvestor1.approve(
    //           weSale.address,
    //           additionalInvestAmount
    //         )
    //         expect(await weSaleConnectInvestor1.invest(additionalInvestAmount))
    //           .not.to.throw

    //         expect(await weSale.getInvestOf(investor1.address)).to.equal(
    //           investAmount.add(additionalInvestAmount)
    //         )
    //       })
    //     })
    //   }
    // })
  })
})

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
