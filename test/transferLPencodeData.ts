import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs'
import { expect } from 'chai'
import { ethers } from 'hardhat'

describe('TransferLPData', function () {
  it('Should can setting new fee to', async function () {
    console.log(
      'InvalidToken(string _origin): ',
      ethers.utils.id('InvalidToken(string)')
    )
    console.log(
      'InvalidNumber(string _origin, uint256 _num): ',
      ethers.utils.id('InvalidNumber(string,uint256)')
    )

    console.log(
      'InsufficientAllowedPresaleAmount(): ',
      ethers.utils.id('InsufficientAllowedPresaleAmount()')
    )
    console.log(
      'InsufficientPresaleBalance(): ',
      ethers.utils.id('InsufficientPresaleBalance()')
    )
    console.log(
      'InsufficientAllowedInvestAmount(): ',
      ethers.utils.id('InsufficientAllowedInvestAmount()')
    )
    console.log(
      'InsufficientInvestBalance(): ',
      ethers.utils.id('InsufficientInvestBalance()')
    )
    console.log(
      'UnsupportedDexRouter(): ',
      ethers.utils.id('UnsupportedDexRouter()')
    )

    console.log(
      'LTMinimumInvestment(): ',
      ethers.utils.id('LTMinimumInvestment()')
    )
    console.log(
      'GTMaximumInvestment(): ',
      ethers.utils.id('GTMaximumInvestment()')
    )
    console.log('InvestmentClosed(): ', ethers.utils.id('InvestmentClosed()'))
    console.log(
      'InvestmentIsNotClosed(): ',
      ethers.utils.id('InvestmentIsNotClosed()')
    )
    console.log(
      'DidNotMeetDivestmentRequirements(): ',
      ethers.utils.id('DidNotMeetDivestmentRequirements()')
    )

    console.log('SaleCompleted(): ', ethers.utils.id('SaleCompleted()'))
    console.log('HasBeenCanceled(): ', ethers.utils.id('HasBeenCanceled()'))
    console.log('IllegalOperation(): ', ethers.utils.id('IllegalOperation()'))
    console.log('Locked(): ', ethers.utils.id('Locked()'))

    console.log('ClaimInvestError(): ', ethers.utils.id('ClaimInvestError()'))
    console.log('ClaimPresaleError(): ', ethers.utils.id('ClaimPresaleError()'))

    console.log(
      'NotAnAutoListingLaunchPad(): ',
      ethers.utils.id('NotAnAutoListingLaunchPad()')
    )
    console.log(
      'IsAnAutoListingLaunchPad(): ',
      ethers.utils.id('IsAnAutoListingLaunchPad()')
    )
    console.log(
      'PresaleNotCompleted(): ',
      ethers.utils.id('PresaleNotCompleted()')
    )
    console.log(
      'TransferAllowedPresaleAmount(): ',
      ethers.utils.id('TransferAllowedPresaleAmount()')
    )
    console.log(
      'TransferPresaleBalanc(): ',
      ethers.utils.id('TransferPresaleBalanc()')
    )
    console.log(
      'TransferAllowedInvestAmount(): ',
      ethers.utils.id('TransferAllowedInvestAmount()')
    )
    console.log(
      'TransferInvestBalance(): ',
      ethers.utils.id('TransferInvestBalance()')
    )
    console.log(
      'TransferLiquidityFailed(): ',
      ethers.utils.id('TransferLiquidityFailed()')
    )
    console.log(
      'TransferLiquiditySignatureVerificationFailed(): ',
      ethers.utils.id('TransferLiquiditySignatureVerificationFailed()')
    )

    const dexRouterBytes = ethers.utils.id('DEX_ROUTER')
    const dexRouterSetterBytes = ethers.utils.id('DEX_ROUTER_SETTER_ROLE')

    console.log('dexRouterBytes: ', dexRouterBytes)
    console.log('dexRouterSetterBytes: ', dexRouterSetterBytes)
    const signer = await ethers.getSigner(
      '0xc71aABBC653C7Bd01B68C35B8f78F82A21014471'
    )
    const routerAddress = '0x29f7Ad37EC018a9eA97D4b3fEebc573b5635fA84'
    const tokenAddress = '0x4C7Ac2e4AC328BB5162CBB45cC6bEAC910F4d37a'
    const teamWallet = '0xA4091e09eB027F1e5D397659bfC7D73CdDdCa276'
    const amountA = ethers.utils.parseEther('0.679').mul(20)
    console.log(amountA)
    const deadline = Math.floor(new Date().getTime() / 1000) + 3600
    let router = await ethers.getContractAt('IUniswapV2Router02', routerAddress)
    let data = router.interface.encodeFunctionData('addLiquiditySYS', [
      tokenAddress,
      amountA,
      0,
      0,
      teamWallet,
      deadline,
    ])

    // const wesale = await ethers.getContractAt(
    //   'WESale',
    //   '0x0e597Fa7b8283726d3ccf01dcfCa01D3b3802Bc8'
    // )

    // const eip = await wesale.eip712Domain()
    // console.log(eip)

    console.log('LPData: ', data)
    const message = {
      domain: {
        name: 'WESale',
        version: '0.0.1',
        chainId: 57000,
        verifyingContract: '0x0e597Fa7b8283726d3ccf01dcfCa01D3b3802Bc8',
      },
      types: {
        TransferLiquidity: [
          { name: '_router', type: 'address' },
          { name: '_amountA', type: 'uint256' },
          { name: '_data', type: 'bytes' },
        ],
      },
      data: {
        _router: routerAddress,
        _amountA: amountA,
        _data:
          '0x3c7356d50000000000000000000000004c7ac2e4ac328bb5162cbb45cc6beac910f4d37a000000000000000000000000000000000000000000000000bc75da0cd1ce000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a4091e09eb027f1e5d397659bfc7d73cdddca2760000000000000000000000000000000000000000000000000000000064956cb1',
      },
    }
    const sign = await signer._signTypedData(
      message.domain,
      message.types,
      message.data
    )
    console.log('sign: ', sign)
    // 从哈希中提取v, r, s
    const sig = ethers.utils.splitSignature(sign)
    console.log(sig.v, sig.r, sig.s)

    // 在js中验证签名
    const recoveredAddress = ethers.utils.verifyTypedData(
      message.domain,
      message.types,
      message.data,
      sig
    )

    console.log('signer add in js file:', recoveredAddress)
  })
})
