// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IWESale.sol";
import "./Error.sol";
import "./WESale.sol";
import "hardhat/console.sol";

contract WESaleFactory is Ownable, AccessControl {
    using SafeMath for uint;

    event WESaleCreated(
        address _creator,
        address _wesale,
        address _presaleToken,
        address _investToken,
        address _teamWallet,
        uint256 _amount,
        Parameters parameters
    );

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant DEX_ROUTER_SETTER_ROLE =
        keccak256("DEX_ROUTER_SETTER_ROLE");
    bytes32 private constant DEX_ROUTER = keccak256("DEX_ROUTER");
    bytes32 private constant WESALES = keccak256("WESALES");
    address public feeTo;
    address public transferSigner;

    string private name = "WESale";
    string private version = "1.0";

    constructor(address _feeTo, address _transferSigner) {
        feeTo = _feeTo;
        transferSigner = _transferSigner;

        _grantRole(ADMIN_ROLE, _msgSender());

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(DEX_ROUTER_SETTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(DEX_ROUTER, DEX_ROUTER_SETTER_ROLE);
    }

    function createSale(
        address _teamWallet,
        address _presaleToken,
        address _investToken,
        Parameters memory _parameters
    ) external payable returns (address wesale) {
        if (_presaleToken == address(0)) {
            revert InvalidToken("ZA");
        }
        if (_parameters.price <= 0) {
            revert InvalidNumber("P", _parameters.price);
        }
        if (_parameters.hardCap <= 0) {
            revert InvalidNumber("HC", _parameters.hardCap);
        }
        if (!hasRole(DEX_ROUTER, _parameters.router)) {
            revert UnsupportedDexRouter();
        }
        IERC20 presaleToken = IERC20(_presaleToken);
        if (_investToken == address(0)) {
            _parameters.investTokenDecimals = 18;
        } else {
            IERC20Metadata investToken = IERC20Metadata(_investToken);
            _parameters.investTokenDecimals = investToken.decimals();
        }
        // investToken.
        uint256 needDepositAmount;
        {
            needDepositAmount = _parameters.hardCap.mul(_parameters.price).div(
                10 ** _parameters.investTokenDecimals
            );
            needDepositAmount = _parameters
                .hardCap
                .mul(_parameters.dexInitPrice)
                .mul(_parameters.liquidityRate)
                .div(1000000)
                .div(10 ** _parameters.investTokenDecimals)
                .add(needDepositAmount);
        }
        if (
            presaleToken.allowance(_msgSender(), address(this)) <
            needDepositAmount
        ) {
            revert InsufficientAllowedPresaleAmount();
        }

        wesale = address(
            new WESale(
                name,
                version,
                _msgSender(),
                _teamWallet,
                _presaleToken,
                _investToken,
                needDepositAmount,
                _parameters
            )
        );

        if (
            !presaleToken.transferFrom(
                _msgSender(),
                address(this),
                needDepositAmount
            )
        ) {
            revert InsufficientPresaleBalance();
        }
        presaleToken.transfer(wesale, needDepositAmount);
        _grantRole(WESALES, wesale);
        emit WESaleCreated(
            _msgSender(),
            wesale,
            _presaleToken,
            _investToken,
            _teamWallet,
            needDepositAmount,
            _parameters
        );
    }

    function setFeeTo(address _feeTo) external onlyRole(ADMIN_ROLE) {
        feeTo = _feeTo;
    }

    function setVersion(string memory _version) external onlyOwner {
        version = _version;
    }

    function setTransferSigner(
        address _transferSigner
    ) external onlyRole(ADMIN_ROLE) {
        transferSigner = _transferSigner;
    }

    function _revokeRole(bytes32 role, address account) internal override {
        if (role == ADMIN_ROLE && account == owner()) {
            revert IllegalOperation();
        }
        AccessControl._revokeRole(role, account);
    }
}
