// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "./Error.sol";
import "./interfaces/IWESaleFactory.sol";

struct Parameters {
    uint256 price;
    uint24 liquidityRate;
    uint256 minInvest;
    uint256 maxInvest;
    uint256 softCap;
    uint256 hardCap;
    address router;
    uint256 dexInitPrice;
    uint256 startedAt;
    uint256 endedAt;
    uint24 firstRelease;
    uint24 cycle;
    uint24 cycleRelease;
    uint24 investTokenDecimals;
}

contract WESale is Ownable, EIP712 {
    using SafeMath for uint;
    // uint256 private presaleReserve;
    // uint256 private investReserve;
    uint256 public unlockedAt;
    uint256 public totalInvest;
    uint256 public totalPresale;
    bool internal isCancel = false;

    uint24 public constant FEE = 30000;
    uint24 public constant URGENT_DIVEST_FEE = 100000;
    address public immutable factory;
    address public immutable presaleToken;
    address public immutable investToken;
    address public immutable teamWallet;
    Parameters public parameters;

    mapping(address => uint256) private investBalances;
    mapping(address => uint256) private claimed;

    event ParticipantDivest(
        address _sender,
        uint256 _amount,
        uint256 _timestamp
    );
    event FounderDivest(address _sender, uint256 _amount, uint256 _timestamp);
    event Invest(address _sender, uint256 _amount, uint256 _timestamp);
    event ClaimInvest(address _sender, uint256 _amount, uint256 _timestamp);
    event ClaimPresale(address _sender, uint256 _amount, uint256 _timestamp);
    event CancelFounderReturn(
        address _sender,
        uint256 _amount,
        uint256 _timestamp
    );
    event CancelReturn(address _sender, uint256 _amount, uint256 _timestamp);
    event Cancel(uint256 _timestamp);
    event TransferLP(
        address _sender,
        address _router,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _timestamp
    );

    uint private unlocked = 0;

    modifier lock() {
        if (unlocked == 1) {
            revert Locked();
        }
        unlocked = 1;
        _;
        unlocked = 0;
    }

    constructor(
        string memory _name,
        string memory _version,
        address _owner,
        address _teamWallet,
        address _presaleToken,
        address _investToken,
        uint256 _deposit,
        Parameters memory _parameters
    ) EIP712(_name, _version) {
        _transferOwnership(_owner);
        factory = _msgSender();
        teamWallet = _teamWallet;
        presaleToken = _presaleToken;
        investToken = _investToken;
        totalPresale = _deposit;
        parameters = _parameters;
    }

    function invest(uint256 investAmount) external payable lock {
        // (uint256 presaleAmount, ) = getAmount(0, investAmount);
        if (parameters.hardCap == totalInvest) {
            revert InvestmentClosed();
        }
        if (investAmount < parameters.minInvest) {
            revert LTMinimumInvestment();
        }
        uint256 _senderTotalInvest = investBalances[_msgSender()].add(
            investAmount
        );
        if (_senderTotalInvest > parameters.maxInvest) {
            revert GTMaximumInvestment();
        }

        if (parameters.hardCap < investAmount.add(totalInvest)) {
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
            if (
                !_investToken.transferFrom(_msgSender(), wesale, investAmount)
            ) {
                revert InsufficientInvestBalance();
            }
        }
        investBalances[_msgSender()] = investBalances[_msgSender()].add(
            investAmount
        );
        totalInvest = totalInvest.add(investAmount);
        emit Invest(_msgSender(), investAmount, block.timestamp);
    }

    function divest() external lock {
        if (_isFailed() || _isCancel()) {
            _divest();
            return;
        }
        if (!_isEnded()) {
            _urgentDivest();
            return;
        }
        revert DidNotMeetDivestmentRequirements();
    }

    function founderDivest() external lock onlyOwner {
        if (_isFailed()) {
            _founderDivest();
            return;
        }
        revert DidNotMeetDivestmentRequirements();
    }

    function transferLiquidity(
        uint256 _amountA,
        bytes calldata _data,
        bytes calldata _signature
    ) external lock onlyOwner {
        if (parameters.router == address(0)) {
            revert NotAnAutoListingLaunchPad();
        }

        if (!_isEnded() || (_isEnded() && totalInvest < parameters.softCap)) {
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

        uint256 amountA = _amountA;
        uint256 amountB = _investTransferLPAmount;
        bytes calldata data = _data;

        IERC20 _investToken = IERC20(investToken);
        IERC20 _presaleToken = IERC20(presaleToken);
        uint256 lockPresaleAmount = totalInvest.mul(parameters.price).div(
            10 ** parameters.investTokenDecimals
        );
        uint256 returnPresaleAmount = totalPresale.sub(amountA).sub(
            lockPresaleAmount
        );
        totalPresale = lockPresaleAmount;

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
        _claimPresaleAmount(_msgSender(), returnPresaleAmount);
        unlockedAt = block.timestamp;

        emit ClaimInvest(
            teamWallet,
            _investTransferTeamAmount,
            block.timestamp
        );
        emit ClaimPresale(_msgSender(), returnPresaleAmount, block.timestamp);
        emit TransferLP(
            _msgSender(),
            parameters.router,
            amountA,
            amountB,
            block.timestamp
        );
    }

    function claimInvest() external lock onlyOwner {
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
        emit ClaimInvest(teamWallet, investAmount, block.timestamp);
    }

    function claimPresale() external lock {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        uint256 totalReleased = getTotalReleased();
        if (totalReleased == 0) {
            revert PresaleNotCompleted();
        }
        // uint256 share = _balance.div(totalInvest);
        uint256 canClaimTotal = totalPresale
            .mul(totalReleased)
            .mul(_balance)
            .div(totalInvest)
            .div(1000000);
        if (canClaimTotal > 0) {
            uint256 _claimed = claimed[_msgSender()];
            uint256 canClaim = canClaimTotal.sub(_claimed);
            if (canClaim > 0) {
                claimed[_msgSender()] = canClaimTotal;
                _claimPresaleAmount(_msgSender(), canClaim);
                emit ClaimPresale(_msgSender(), canClaim, block.timestamp);
            }
        }
    }

    function cancel() external lock {
        if (unlockedAt != 0) {
            revert SaleCompleted();
        }
        if (_isCancel()) {
            revert HasBeenCanceled();
        }
        isCancel = true;
        _claimPresaleAmount(_msgSender(), totalPresale);
        emit CancelFounderReturn(_msgSender(), totalPresale, block.timestamp);
    }

    function getTotalReleased() public view returns (uint256) {
        if (unlockedAt == 0 || block.timestamp < unlockedAt) {
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
            investAmount = presaleAmount
                .mul(10 ** parameters.investTokenDecimals)
                .div(parameters.price);
        } else {
            presaleAmount = investAmount.mul(parameters.price).div(
                10 ** parameters.investTokenDecimals
            );
        }
        return (presaleAmount, investAmount);
    }

    function getInvestOf(address investor) external view returns (uint256) {
        return investBalances[investor];
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
        totalInvest = totalInvest.sub(_balance);
        _claimInvestAmount(_msgSender(), _balance);
        emit ParticipantDivest(_msgSender(), _balance, block.timestamp);
    }

    function _urgentDivest() internal {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        _balance = _balance.mul(URGENT_DIVEST_FEE).div(1000000);
        investBalances[_msgSender()] = 0;
        totalInvest = totalInvest.sub(_balance);
        _claimInvestAmount(_msgSender(), _balance);
        emit ParticipantDivest(_msgSender(), _balance, block.timestamp);
    }

    function _founderDivest() internal {
        totalPresale = 0;
        IERC20 _presaleToken = IERC20(presaleToken);
        uint256 _presaleTokenAmunt = _presaleToken.balanceOf(address(this));
        if (_presaleTokenAmunt == 0) {
            return;
        }
        _claimPresaleAmount(_msgSender(), _presaleTokenAmunt);
        emit FounderDivest(_msgSender(), totalPresale, block.timestamp);
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

    function _isCancel() public view returns (bool) {
        return isCancel;
    }

    function _isLive() public view returns (bool) {
        return _isStarted() && !_isEnded();
    }

    function _isStarted() public view returns (bool) {
        return block.timestamp >= parameters.startedAt;
    }

    function _isEnded() public view returns (bool) {
        return block.timestamp >= parameters.endedAt;
    }

    function _isNative() public view returns (bool) {
        return investToken == address(0);
    }

    function _isFailed() public view returns (bool) {
        return _isEnded() && totalInvest < parameters.softCap;
    }
}
