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
    bool internal canUpdate = true;

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
    // event ClaimInvest(address _sender, uint256 _amount, uint256 _timestamp);
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
    event UpdateEndedAt(uint256 _timestamp);

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

    // 更新预售结束时间，必须大于旧结束时间
    function updateEndedAt(uint256 _endedAt) external onlyOwner {
        if (_isEnded() || !_canUpdate() || _isCancel()) {
            revert EditingIsCurrentlyNotAllowed();
        }
        if (parameters.endedAt > _endedAt) {
            revert MustAfterOld();
        }
        parameters.endedAt = _endedAt;
        canUpdate = false;
        emit UpdateEndedAt(_endedAt);
    }

    // 投资，允许所有人在设置范围内进行投资
    function invest(uint256 investAmount) external payable lock {
        if (_isCancel()) {
            revert HasBeenCanceled();
        }
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

    // 投资人正常撤资或紧急撤资
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

    // 发起人撤资
    function founderDivest() external lock onlyOwner {
        if (_isFailed()) {
            _founderDivest();
            return;
        }
        revert DidNotMeetDivestmentRequirements();
    }

    // 转移流动性，设置过转移流动性，并且预售成功后可以转移流动性
    function transferLiquidity(
        uint256 _amountA,
        bytes calldata _data,
        bytes calldata _signature
    ) external lock onlyOwner {
        if (_isCancel()) {
            revert HasBeenCanceled();
        }
        if (parameters.router == address(0)) {
            revert NotAnAutoListingLaunchPad();
        }

        if (unlockedAt != 0) {
            revert SaleCompleted();
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
            ,
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
        if (_isNative()) {
            _claimInvestAmount(teamWallet, address(this).balance);
        } else {
            _claimInvestAmount(
                teamWallet,
                _investToken.balanceOf(address(this))
            );
        }
        _claimPresaleAmount(_msgSender(), returnPresaleAmount);
        unlockedAt = block.timestamp;

        // emit ClaimInvest(
        //     teamWallet,
        //     _investTransferTeamAmount,
        //     block.timestamp
        // );
        emit ClaimPresale(_msgSender(), returnPresaleAmount, block.timestamp);
        emit TransferLP(
            _msgSender(),
            parameters.router,
            amountA,
            amountB,
            block.timestamp
        );
    }

    // 认领投资token，非转移流动性预售可以调用
    function claimInvest() external lock onlyOwner {
        if (_isCancel()) {
            revert HasBeenCanceled();
        }
        if (parameters.router != address(0)) {
            revert IsAnAutoListingLaunchPad();
        }
        if (_isFailed()) {
            revert ClaimInvestError();
        }
        if (!_isEnded() || totalInvest < parameters.softCap) {
            revert InvestmentIsNotClosed();
        }
        if (unlockedAt != 0) {
            revert SaleCompleted();
        }
        IWESaleFactory _factory = IWESaleFactory(factory);
        address feeTo = _factory.feeTo();
        uint256 fee = totalInvest.mul(FEE).div(1000000);
        uint256 investAmount = totalInvest.sub(fee);
        _claimInvestAmount(feeTo, fee);
        _claimInvestAmount(teamWallet, investAmount);
        unlockedAt = block.timestamp;
        // emit ClaimInvest(teamWallet, investAmount, block.timestamp);
    }

    // function test() external {
    //     // investBalances[_msgSender()] = 100_000_000_000_000_000;
    //     // totalInvest = 100_000_000_000_000_000;
    //     unlockedAt = block.timestamp;
    // }

    // 预售成功后投资人认领预售token，根据设置的认领规则
    function claimPresale() external lock {
        if (_isFailed() || unlockedAt == 0) {
            revert PresaleNotCompleted();
        }
        // uint256 share = _balance.div(totalInvest);
        (uint256 canClaimTotal, uint256 canClaim) = getCanClaimTotal();
        if (canClaim > 0) {
            claimed[_msgSender()] = canClaimTotal;
            _claimPresaleAmount(_msgSender(), canClaim);
            emit ClaimPresale(_msgSender(), canClaim, block.timestamp);
        }
    }

    // 获取投资人可认领的预售token数量
    function getCanClaimTotal() public view returns (uint256, uint256) {
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

        uint256 canClaim = 0;
        if (canClaimTotal > 0) {
            uint256 _claimed = getClaimedTotal();
            canClaim = canClaimTotal.sub(_claimed);
        }
        return (canClaimTotal, canClaim);
    }

    // 获取已认领预售token的数量
    function getClaimedTotal() public view returns (uint256) {
        return claimed[_msgSender()];
    }

    // 取消预售
    function cancel() external lock onlyOwner {
        if (unlockedAt != 0) {
            revert SaleCompleted();
        }
        if (_isCancel()) {
            revert HasBeenCanceled();
        }
        isCancel = true;
        _claimPresaleAmount(_msgSender(), totalPresale);
        emit Cancel(block.timestamp);
        emit CancelFounderReturn(_msgSender(), totalPresale, block.timestamp);
    }

    // 获取可释放的token的比例
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

    // 获取转移流动性的投资token以及预售token的数量
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

    // 获取交易投资token或预售token的数量
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

    // 获取预售投资金额
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
    // 撤资
    function _divest() internal {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        investBalances[_msgSender()] = 0;
        _claimInvestAmount(_msgSender(), _balance);
        if (!_isCancel()) {
            totalInvest = totalInvest.sub(_balance);
            emit ParticipantDivest(_msgSender(), _balance, block.timestamp);
        }
    }

    // 紧急撤资，扣除手续费
    function _urgentDivest() internal {
        uint256 _balance = investBalances[_msgSender()];
        if (_balance == 0) {
            revert InsufficientInvestBalance();
        }
        uint256 _fee = _balance.mul(URGENT_DIVEST_FEE).div(1000000);
        investBalances[_msgSender()] = 0;
        uint256 returnInvest = _balance.sub(_fee);
        totalInvest = totalInvest.sub(_balance);

        IWESaleFactory _factory = IWESaleFactory(factory);
        address feeTo = _factory.feeTo();
        _claimInvestAmount(feeTo, _fee);

        _claimInvestAmount(_msgSender(), returnInvest);
        emit ParticipantDivest(_msgSender(), returnInvest, block.timestamp);
    }

    // 发起人撤资
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

    // 认领投资token
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

    // 认领预售token
    function _claimPresaleAmount(address recipient, uint256 _amount) internal {
        IERC20 _presaleToken = IERC20(presaleToken);
        bool success = _presaleToken.transfer(recipient, _amount);
        if (!success) {
            revert ClaimPresaleError();
        }
    }

    // 获取hash签名
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

    // 验证签名
    function _verify(
        address _signer,
        bytes32 _hash,
        bytes calldata _signature
    ) internal pure returns (bool) {
        return ECDSA.recover(_hash, _signature) == _signer;
    }

    // 是否已取消
    function _isCancel() public view returns (bool) {
        return isCancel;
    }

    // 是否活跃
    function _isLive() public view returns (bool) {
        return _isStarted() && !_isEnded();
    }

    // 是否开始
    function _isStarted() public view returns (bool) {
        return block.timestamp >= parameters.startedAt;
    }

    // 是否结束
    function _isEnded() public view returns (bool) {
        return block.timestamp >= parameters.endedAt;
    }

    // 是否是原生币作为投资token
    function _isNative() public view returns (bool) {
        return investToken == address(0);
    }

    // 是否失败
    function _isFailed() public view returns (bool) {
        return _isEnded() && totalInvest < parameters.softCap;
    }

    // 是否可更改
    function _canUpdate() public view returns (bool) {
        return canUpdate;
    }
}
