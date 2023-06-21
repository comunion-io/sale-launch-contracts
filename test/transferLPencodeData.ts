import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs'
import { expect } from 'chai'
import { ethers } from 'hardhat'

describe('TransferLPData', function () {
  it('Should can setting new fee to', async function () {
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
        _data: data,
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
