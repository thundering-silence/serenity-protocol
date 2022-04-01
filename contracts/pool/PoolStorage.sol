// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../feesCollector/interfaces/IFeesCollector.sol";
import "./interfaces/IPoolStorage.sol";
import "../libraries/DataTypesLib.sol";
import "../membership/interfaces/IThermae.sol";
import "../oracle/interfaces/IPriceOracle.sol";
import "../rewards/interfaces/IRewardsManager.sol";

abstract contract PoolStorage is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DELEGATOR_ROLE = keccak256("DELEGATOR_ROLE");
    bytes32 public constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    IERC20 public immutable _underlying;
    IPriceOracle internal _oracle;
    IFeesCollector internal _feesCollector;
    IThermae internal _thermae;
    IRewardsManager internal _rewardsManager;

    DataTypes.LendingConfig internal _lendingConfig;
    DataTypes.InterestRateConfig internal _rateConfig;
    DataTypes.FlashLoanConfig internal _flashLoanConfig;

    uint256 internal _index = 1e18; // keeps track of interest for Loans
    uint256 internal _depositIndex = 1e18; // keeps track of interest for Supply
    uint256 internal _lastIndexUpdateTimestamp = block.timestamp; // keeps track of the last time indexes were updated

    uint256 internal _totalLoans;
    uint256 internal _totalDeposits;
    struct Snapshot {
        uint256 amount;
        uint256 index;
        uint256 accruedInterest;
    }
    mapping(address => Snapshot) internal _debts; // keep track of debt for each account
    mapping(address => Snapshot) internal _deposits; // keep track of deposits for each account;
    mapping(address => bool) internal _collaterals; // for which accounts is this used as collateral?
    mapping(address => mapping(address => uint256)) internal _borrowAllowances;
    mapping(address => mapping(address => uint256))
        internal _withdrawAllowances;

    event OracleUpdate(address indexed oracle);
    event FeesCollectorUpdate(address indexed collector);
    event RewardsManagerUpdate(address indexed manager);
    event LendingConfigUpdate(
        uint256 col,
        uint256 liq,
        uint256 fee,
        uint256 grace
    );
    event InterestRateConfigUpdate(
        uint256 base,
        uint256 s1,
        uint256 s2,
        uint256 u
    );
    event FlashLoanConfigUpdate(bool active, uint256 fee);

    constructor(
        address underlying_,
        address oracle_,
        address feesCollector_,
        address spa_,
        address admin_,
        DataTypes.LendingConfig memory lendingConfig_,
        DataTypes.InterestRateConfig memory interestRateConfig_,
        DataTypes.FlashLoanConfig memory flashLoanConfig_
    ) {
        require(admin_ != address(0));

        _underlying = IERC20(underlying_);
        _oracle = IPriceOracle(oracle_);
        _feesCollector = IFeesCollector(feesCollector_);
        _thermae = IThermae(spa_);

        _lendingConfig = lendingConfig_;
        _rateConfig = interestRateConfig_;
        _flashLoanConfig = flashLoanConfig_;

        _setupRole(DEFAULT_ADMIN_ROLE, admin_);
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(DELEGATOR_ROLE, _msgSender());
    }

    // READ METHODS
    function underlying() public view returns (address) {
        return address(_underlying);
    }

    function oracle() public view returns (address) {
        return address(_oracle);
    }

    function spa() public view returns (address) {
        return address(_thermae);
    }

    function feesCollector() public view returns (address) {
        return address(_feesCollector);
    }

    function rewardsManager() public view returns (address) {
        return address(_rewardsManager);
    }

    function lendingConfig()
        public
        view
        returns (DataTypes.LendingConfig memory)
    {
        return _lendingConfig;
    }

    function interestRateConfig()
        public
        view
        returns (DataTypes.InterestRateConfig memory)
    {
        return _rateConfig;
    }

    function flashLoanConfig()
        public
        view
        returns (DataTypes.FlashLoanConfig memory)
    {
        return _flashLoanConfig;
    }

    function index() public view returns (uint256) {
        return _index;
    }

    function totalLoans() public view returns (uint256) {
        return _totalLoans;
    }

    function totalDeposits() public view returns (uint256) {
        return _totalDeposits;
    }

    // ADMIN METHODS
    function updateOracle(address oracle_) public onlyRole(ADMIN_ROLE) {
        _oracle = IPriceOracle(oracle_);
        emit OracleUpdate(oracle_);
    }

    function updateFeesCollector(IFeesCollector feesCollector_)
        public
        onlyRole(ADMIN_ROLE)
    {
        _feesCollector = feesCollector_;
        emit FeesCollectorUpdate(address(feesCollector_));
    }

    function updateRewardsManager(address manager) public onlyRole(ADMIN_ROLE) {
        _rewardsManager = IRewardsManager(manager);
        emit RewardsManagerUpdate(manager);
    }

    function updateLendingConfig(DataTypes.LendingConfig memory lendingConfig_)
        public
        onlyRole(ADMIN_ROLE)
    {
        _lendingConfig = lendingConfig_;
        emit LendingConfigUpdate(
            _lendingConfig.collateralFactor,
            _lendingConfig.liquidationFee,
            _lendingConfig.fee,
            _lendingConfig.maxLiquidationThreshold
        );
    }

    function updateInterestRateConfig(
        DataTypes.InterestRateConfig memory interestRateConfig_
    ) public onlyRole(ADMIN_ROLE) {
        _rateConfig = interestRateConfig_;
        emit InterestRateConfigUpdate(
            _rateConfig.baseRate,
            _rateConfig.slope1,
            _rateConfig.slope2,
            _rateConfig.optimalUtilisation
        );
    }

    function updateFlashLoanConfig(
        DataTypes.FlashLoanConfig memory flashLoanConfig_
    ) public onlyRole(ADMIN_ROLE) {
        _flashLoanConfig = flashLoanConfig_;
        emit FlashLoanConfigUpdate(
            _flashLoanConfig.active,
            _flashLoanConfig.fee
        );
    }
}
