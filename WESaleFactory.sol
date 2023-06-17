// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IWESale.sol";
import "./Error.sol";
import "./WESale.sol";

contract WESaleFactory is Ownable, AccessControl {
    using SafeMath for uint256;

    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant DEX_ROUTER_SETTER_ROLE =
        keccak256("DEX_ROUTER_SETTER_ROLE");
    bytes32 private constant DEX_ROUTER = keccak256("DEX_ROUTER");
    bytes32 private constant WESALES = keccak256("WESALES");
    address public feeTo;
    address public transferSigner;

    string private name = "WESale";
    string private version = "0.0.1";

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
        Parameters calldata _parameters
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
        // //  TODO SafeMath
        uint256 needDepositAmount;
        {
            needDepositAmount = _parameters.hardCap.mul(_parameters.price);
            needDepositAmount = _parameters
                .hardCap
                .mul(_parameters.dexInitPrice)
                .mul(_parameters.liquidityRate)
                .div(1000000)
                .add(needDepositAmount);
        }

        IERC20 presaleToken = IERC20(_presaleToken);
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
                needDepositAmount
            )
        );

        if (
            presaleToken.transferFrom(_msgSender(), wesale, needDepositAmount)
        ) {
            revert InsufficientPresaleBalance();
        }
        _grantRole(WESALES, wesale);
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
