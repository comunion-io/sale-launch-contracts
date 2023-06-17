// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "./Error.sol";
import "./interfaces/IWESaleFactory.sol";

struct Parameters {
    uint256 price;
    uint256 liquidityRate;
    uint256 minInvest;
    uint256 maxInvest;
    uint256 softCap;
    uint256 hardCap;
    address router;
    uint256 dexInitPrice;
    uint256 startedAt;
    uint256 endedAt;
    uint256 firstRelease;
    uint256 cycle;
    uint256 cycleRelease;
}

contract WESale is Ownable, EIP712 {
    using SafeMath for uint256;
    // uint256 private presaleReserve;
    // uint256 private investReserve;
    string public name;
    string public version;
    uint256 public unlockedAt;
    uint256 public totalInvest;
    uint256 public totalPresale;

    uint24 public constant FEE = 30000;
    address public immutable factory;
    address public immutable presaleToken;
    address public immutable investToken;
    address public immutable teamWallet;
    Parameters public parameters;

    mapping(address => uint256) private investBalances;
    mapping(address => uint256) private claimed;

    uint private unlocked = 1;

    modifier lock() {
        if (unlocked == 1) {
            revert Locked();
        }
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(
        string memory _name,
        string memory _version,
        address _owner,
        address _teamWallet,
        address _presaleToken,
        address _investToken,
        uint256 _deposit
    ) EIP712(_name, _version) {
        Parameters memory _parameters;

        _transferOwnership(_owner);
        name = _name;
        name = _version;
        factory = _msgSender();
        teamWallet = _teamWallet;
        presaleToken = _presaleToken;
        investToken = _investToken;
        totalPresale = _deposit;
        parameters = _parameters;
    }

    function invest(uint256 presaleAmount) external payable lock {
        (, uint256 investAmount) = getAmount(presaleAmount, 0);
        if (parameters.hardCap == totalInvest) {}
        // (, uint256 _investReserve ) = getReserves();
        uint256 allowInvestAmount = parameters.hardCap.mul(totalInvest);
        if (allowInvestAmount < presaleAmount) {
            revert InvalidNumber("AIA", investAmount);
        }
        if (_isNative()) {
            if (investAmount != msg.value) {
                revert InvalidNumber("NIA", msg.value);
            }
        } else {
            IERC20 _investToken = IERC20(investToken);
            address wesale = address(this);
            if (_investToken.allowance(_msgSender(), wesale) < investAmount) {
                revert InsufficientAllowedInvestAmount();
            }
            if (_investToken.transferFrom(_msgSender(), wesale, investAmount)) {
                revert InsufficientInvestBalance();
            }
        }
        investBalances[_msgSender()] = investBalances[_msgSender()].add(
            investAmount
        );
        totalInvest = totalInvest.add(investAmount);
    }

    function divest() external lock {
        if (
            totalInvest < parameters.softCap ||
            (!_isEnded() && totalInvest < parameters.hardCap)
        ) {
            _divest();
            return;
        }
        revert DidNotMeetDivestmentRequirements();
    }

    function founderDivest() external lock onlyOwner {
        if (_isFailed()) {
            revert DidNotMeetDivestmentRequirements();
        }
        _founderDivest();
    }

    function transferLiquidity(
        uint256 _amountA,
        bytes calldata _data,
        bytes calldata _signature
    ) external lock onlyOwner {
        if (parameters.router == address(0)) {
            revert NotAnAutoListingLaunchPad();
        }
        if (
            totalInvest < parameters.softCap ||
            (totalInvest < parameters.hardCap && !_isEnded())
        ) {
            revert PresaleNotCompleted();
        }

        uint256 maxAmount = totalPresale.mul(parameters.liquidityRate).div(
            1000000
        );
        if (maxAmount < _amountA || _amountA == 0) {
            revert IllegalOperation();
        }

        IWESaleFactory _factory = IWESaleFactory(factory);

        if (
            _verify(
                _factory.transferSigner(),
                getHash(parameters.router, _amountA, _data),
                _signature
            )
        ) {
            revert TransferLiquiditySignatureVerificationFailed();
        }

        (
            uint256 _investTransferLPAmount,
            uint256 _investTransferTeamAmount,
            uint256 _fee
        ) = getTransferLiquidityInvestAmount();
        address feeTo = _factory.feeTo();

        totalPresale = totalPresale.sub(_amountA);

        uint256 amountA = _amountA;
        uint256 amountB = _investTransferLPAmount;
        bytes calldata data = _data;

        IERC20 _investToken = IERC20(investToken);
        IERC20 _presaleToken = IERC20(presaleToken);

        bool success = _presaleToken.approve(parameters.router, amountA);
        if (!success) {
            revert TransferAllowedPresaleAmount();
        }
        // bool success;
        if (_isNative()) {
            (success, ) = parameters.router.call{value: amountB}(data);
            if (!success) {
                revert TransferLiquidityFailed();
            }
        } else {
            success = _investToken.approve(parameters.router, amountB);
            if (!success) {
                revert TransferAllowedInvestAmount();
            }

            (success, ) = parameters.router.call(data);
            if (!success) {
                revert TransferLiquidityFailed();
            }
        }
        _claimInvestAmount(feeTo, _fee);
        _claimInvestAmount(teamWallet, _investTransferTeamAmount);
        unlockedAt = block.timestamp;
    }

    function cliamInvest() external lock onlyOwner {
        if (parameters.router != address(0)) {
            revert IsAnAutoListingLaunchPad();
        }
        if (_isFailed()) {
            revert ClaimInvestError();
        }
        if (!_isEnded() || totalInvest != parameters.hardCap) {
            revert InvestmentIsNotClosed();
        }
        IWESaleFactory _factory = IWESaleFactory(factory);
        address feeTo = _factory.feeTo();
        uint256 fee = totalInvest.mul(FEE).div(1000000);
        uint256 investAmount = totalInvest.sub(fee);
        _claimInvestAmount(feeTo, fee);
        _claimInvestAmount(teamWallet, investAmount);
    }

    function claimPresale() external lock {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        uint256 totalReleased = getTotalReleased();
        uint256 share = _balance.div(totalInvest);
        uint256 canClaimTotal = totalReleased.mul(share).div(1000000);
        if (canClaimTotal > 0) {
            uint256 _claimed = claimed[_msgSender()];
            uint256 canClaim = canClaimTotal.sub(_claimed);
            if (canClaim > 0) {
                claimed[_msgSender()] = canClaimTotal;
                _claimPresaleAmount(_msgSender(), canClaim);
            }
        }
    }

    function getTotalReleased() public view returns (uint256) {
        if (block.timestamp < unlockedAt) {
            return 0;
        }
        uint256 cycleCount = 0;
        uint256 interval = block.timestamp.sub(unlockedAt);
        if (interval > parameters.cycle) {
            cycleCount = interval.div(parameters.cycle);
        }
        uint256 totalReleasePercentage = parameters.firstRelease;
        if (cycleCount > 0) {
            totalReleasePercentage = cycleCount
                .mul(parameters.cycleRelease)
                .add(totalReleasePercentage);
        }
        if (totalReleasePercentage > 1000000) {
            return 1000000;
        }
        return totalReleasePercentage;
    }

    function getTransferLiquidityInvestAmount()
        public
        view
        returns (
            uint256 _investTransferLPAmount,
            uint256 _investTransferTeamAmount,
            uint256 _fee
        )
    {
        _fee = totalInvest.mul(FEE).div(1000000);
        uint256 _total = totalInvest.sub(_fee);
        _investTransferLPAmount = _total.mul(parameters.liquidityRate).div(
            1000000
        );
        _investTransferTeamAmount = _total.sub(_investTransferLPAmount);
        return (_investTransferLPAmount, _investTransferTeamAmount, _fee);
    }

    function getAmount(
        uint256 presaleAmount,
        uint256 investAmount
    ) public view returns (uint256 _presaleAmount, uint256 _investAmount) {
        if (presaleAmount > 0) {
            investAmount = presaleAmount.mul(parameters.price);
        } else {
            presaleAmount = investAmount.div(parameters.price);
        }
        return (presaleAmount, investAmount);
    }

    // function getReserves()
    //     public
    //     view
    //     returns (uint256 _presaleReserve, uint256 _investReserve)
    // {
    //     _presaleReserve = presaleReserve;
    //     _investReserve = investReserve;
    // }

    function _divest() internal {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        investBalances[_msgSender()] = 0;
        _claimInvestAmount(_msgSender(), _balance);
    }

    function _founderDivest() internal {
        _claimInvestAmount(_msgSender(), totalPresale);
    }

    function _claimInvestAmount(address recipient, uint256 _amount) internal {
        bool success;
        if (_isNative()) {
            (success, ) = recipient.call{value: _amount}("");
        } else {
            IERC20 _investToken = IERC20(investToken);
            success = _investToken.transfer(recipient, _amount);
        }
        if (!success) {
            revert ClaimInvestError();
        }
    }

    function _claimPresaleAmount(address recipient, uint256 _amount) internal {
        IERC20 _presaleToken = IERC20(presaleToken);
        bool success = _presaleToken.transfer(recipient, _amount);
        if (!success) {
            revert ClaimPresaleError();
        }
    }

    function getHash(
        address _router,
        uint256 _amountA,
        bytes calldata _data
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "TransferLiquidity(address _router,uint256 _amountA,bytes calldata _data)"
                        ),
                        _amountA,
                        _router,
                        _data
                    )
                )
            );
    }

    function _verify(
        address _signer,
        bytes32 _hash,
        bytes calldata _signature
    ) internal pure returns (bool) {
        return ECDSA.recover(_hash, _signature) == _signer;
    }

    function _isLive() public view returns (bool) {
        return _isStarted() && !_isEnded();
    }

    function _isStarted() public view returns (bool) {
        return block.timestamp >= parameters.startedAt;
    }

    function _isEnded() public view returns (bool) {
        return block.timestamp <= parameters.endedAt;
    }

    function _isNative() public view returns (bool) {
        return investToken == address(0);
    }

    function _isFailed() public view returns (bool) {
        return _isEnded() && totalInvest < parameters.softCap;
    }
}
