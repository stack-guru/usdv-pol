// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./interfaces/ISlayer.sol";

/// @notice ChainLink Aggregator interfaces used for getting BTC ve ETH prices in real time
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

abstract contract IERC20Extented is IERC20 {
    function decimals() public view virtual returns (uint8);

    function burn(uint256 value) public virtual;
}

contract USDVContract is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeCast for int256;

    IERC20Extented public currencyToken;

    uint256 public constant BASIS_POINTS = 10000;

    AggregatorV3Interface public dataFeedBtc;
    AggregatorV3Interface public dataFeedEth;

    bool public isPublicMintOpen;

    bool public isPublicRedeemOpen;

    bool public isClaimOpen;

    bool public isExchange_1_Open;

    bool public isExchange_2_Open;

    bool public isCheckINOpen;

    address treasuryWallet;

    uint256 public tokenPrice;

    uint256 public minusMint;

    uint256 public burnFee;

    uint256 public minBurnAmount;

    uint256 public mintFeePercent;

    uint256 public exchange_1_TreasuryFeePercent;

    uint256 public exchange_1_LPFeePercent;

    uint256 public exchange_2_TreasuryFeePercent;

    uint256 public exchange_2_LPFeePercent;

    uint256 public checkINFrequency;

    uint256 public checkINEarnRate;

    ISlayer public PhoenixToken;
    ISlayer public HeavenToken;

    mapping(address => bool) public whiteListed;

    mapping(address => uint256) public lastCheckIN;

    mapping(address => uint256) public userTotalCheckINs;

    mapping(address => uint256) public totalEarnsForUser;

    mapping(address => uint256) public userCheckInCounter;

    mapping(address => mapping(uint256 => uint256))
        public userCheckINTimestamps;

    event mintTokenEvent(
        address user,
        uint256 tax,
        uint256 amount,
        uint256 amountTransfered,
        uint256 mintAmount,
        uint256 minusMint,
        uint256 timestamp
    );
    event redeemTokenEvent(
        address user,
        uint256 amount,
        uint256 transferAmount,
        uint256 tokenPrice,
        uint256 timestamp
    );
    event InsufficientFundEvent(
        address user,
        uint256 amount,
        uint256 transferAmount,
        uint256 tokenPrice,
        uint256 timestamp,
        uint256 contractBalance
    );
    event checkINEvent(
        address user,
        uint256 lastCheckIN,
        uint256 newEarn,
        uint256 totalEarned,
        uint256 timestamp,
        uint256 checkINEarnRate
    );
    event claimEvent(address user, uint256 amount);
    event Exchange_1_Event(
        address user,
        uint256 amount,
        uint256 assetPriceETH,
        uint256 phoenixUSDTPrice,
        uint256 tokenPrice,
        uint256 usdvPriceInUSDT,
        uint256 value,
        int256 answer
    );
    event Exchange_2_Event(
        address user,
        uint256 amount,
        uint256 assetPriceETH,
        uint256 phoenixUSDTPrice,
        uint256 tokenPrice,
        uint256 usdvPriceInUSDT,
        uint256 value,
        int256 answer
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("USDV", "USDV");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        minBurnAmount = 1000000;
        burnFee = 0;
        tokenPrice = 1250000;
        minusMint = 1000000;
        isPublicMintOpen = false;
        isPublicRedeemOpen = false;
        mintFeePercent = 10;
        exchange_1_TreasuryFeePercent = 500;
        exchange_1_LPFeePercent = 1000;
        exchange_2_TreasuryFeePercent = 500;
        exchange_2_LPFeePercent = 1000;
        treasuryWallet = 0x44F1136f94967ED9846Be3113B2aB447e5827258;
        isCheckINOpen = true;
        currencyToken = IERC20Extented(
            0xc2132D05D31c914a87C6611C10748AEb04B58e8F
        );
        PhoenixToken = ISlayer(payable(address(0)));
        HeavenToken = ISlayer(payable(address(0)));

        checkINFrequency = 1 days;
        checkINEarnRate = 10000;
    }

    function mintToken(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0);
        if (!isPublicMintOpen) {
            require(msg.sender == owner(), "Not Authorized");
        }

        uint256 beforeBalance_1 = currencyToken.balanceOf(address(this));
        require(
            currencyToken.transferFrom(msg.sender, address(this), _amount),
            "Fee Transfer Problem 1"
        );
        uint256 AfterBalance_1 = currencyToken.balanceOf(address(this));

        uint256 amountTransfered = AfterBalance_1 - beforeBalance_1;

        uint256 _tax = (amountTransfered * mintFeePercent) / BASIS_POINTS;
        uint256 _tokenAmountToMint = (amountTransfered * 10**6) / tokenPrice;
        require(_tokenAmountToMint > minusMint, "Problem 1");

        require(
            currencyToken.transferFrom(msg.sender, treasuryWallet, _tax),
            "Fee Transfer Problem 1"
        );

        _tokenAmountToMint = _tokenAmountToMint - minusMint;
        _mint(msg.sender, _tokenAmountToMint);
        emit mintTokenEvent(
            msg.sender,
            _tax,
            _amount,
            amountTransfered,
            _tokenAmountToMint,
            minusMint,
            block.timestamp
        );
    }

    function redeemToken(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0);
        if (!isPublicRedeemOpen) {
            require(msg.sender == owner(), "Not Authorized");
        }

        uint256 _tokenAmountToTransfer = (_amount * tokenPrice) / 10**6;
        if (currencyToken.balanceOf(address(this)) >= _tokenAmountToTransfer) {
            require(
                currencyToken.transfer(msg.sender, _tokenAmountToTransfer),
                "Transfer Problem 2"
            );

            _burn(msg.sender, _amount);
            emit redeemTokenEvent(
                msg.sender,
                _amount,
                _tokenAmountToTransfer,
                tokenPrice,
                block.timestamp
            );
        } else {
            emit InsufficientFundEvent(
                msg.sender,
                _amount,
                _tokenAmountToTransfer,
                tokenPrice,
                block.timestamp,
                currencyToken.balanceOf(address(this))
            );
            revert("Not Enough Balance on Contract");
        }
    }

    function checkIN() external nonReentrant whenNotPaused {
        if (!isCheckINOpen) {
            require(msg.sender == owner(), "Not Authorized");
        }
        require(whiteListed[msg.sender], "Not Authorized");
        uint256 _tmpCheck = 0;
        if (
            (lastCheckIN[msg.sender] == 0) ||
            ((block.timestamp - lastCheckIN[msg.sender]) > checkINFrequency)
        ) {
            _tmpCheck = lastCheckIN[msg.sender];
            lastCheckIN[msg.sender] = block.timestamp;
            userTotalCheckINs[msg.sender]++;
            totalEarnsForUser[msg.sender] =
                totalEarnsForUser[msg.sender] +
                (((10**6) * checkINEarnRate) / BASIS_POINTS);

            userCheckINTimestamps[msg.sender][
                userCheckInCounter[msg.sender]++
            ] = block.timestamp;
            emit checkINEvent(
                msg.sender,
                _tmpCheck,
                (((10**6) * checkINEarnRate) / BASIS_POINTS),
                totalEarnsForUser[msg.sender],
                block.timestamp,
                checkINEarnRate
            );
        } else {
            revert("Cant CheckIN again");
        }
    }

    function claim() external nonReentrant whenNotPaused {
        require(whiteListed[msg.sender], "Not Authorized");
        if (!isClaimOpen) {
            require(msg.sender == owner(), "Not Authorized");
        }

        if (totalEarnsForUser[msg.sender] > 0) {
            require(
                IERC20Extented(address(this)).transfer(
                    msg.sender,
                    totalEarnsForUser[msg.sender]
                ),
                "Transfer Problem 3"
            );
            emit claimEvent(msg.sender, totalEarnsForUser[msg.sender]);

            totalEarnsForUser[msg.sender] = 0;
            userTotalCheckINs[msg.sender] = 0;
        }
    }

    function Exchange_1(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0);
        require(whiteListed[msg.sender], "Not Authorized");
        if (!isExchange_1_Open) {
            require(msg.sender == owner(), "Not Authorized");
        }
        uint256 assetPriceETH = PhoenixToken.tokenPrice();
        (int256 answer, uint256 timeStamp) = getChainlinkDataFeedLatestAnswer(
            false
        );
        if ((block.timestamp - timeStamp) > 30) {
            revert("Old Price Feed");
        }
        uint256 phoenixUSDTPrice = (assetPriceETH * (answer.toUint256())) /
            10**20;
        uint256 usdvPriceInUSDT = (_amount * tokenPrice) / 10**6;
        uint256 value = (usdvPriceInUSDT * 10**6) / phoenixUSDTPrice;
        uint256 ownerTax = (value * exchange_1_TreasuryFeePercent) /
            BASIS_POINTS;
        uint256 LPTax = (value * exchange_1_LPFeePercent) / BASIS_POINTS;
        if (value > (ownerTax + LPTax)) {
            _burn(msg.sender, _amount);

            require(
                PhoenixToken.transfer(treasuryWallet, (ownerTax)),
                "Transfer Problem 5"
            );

            require(
                PhoenixToken.transfer(msg.sender, (value - ownerTax - LPTax)),
                "Transfer Problem 6"
            );

            emit Exchange_1_Event(
                msg.sender,
                _amount,
                assetPriceETH,
                phoenixUSDTPrice,
                tokenPrice,
                usdvPriceInUSDT,
                (value - ownerTax - LPTax),
                answer
            );
        }
    }

    function Exchange_2(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0);
        require(whiteListed[msg.sender], "Not Authorized");
        if (!isExchange_2_Open) {
            require(msg.sender == owner(), "Not Authorized");
        }
        uint256 assetPriceBTC = HeavenToken.tokenPrice();
        (int256 answer, uint256 timeStamp) = getChainlinkDataFeedLatestAnswer(
            true
        );
        if ((block.timestamp - timeStamp) > 30) {
            revert("Old Price Feed");
        }
        uint256 heavenUSDTPrice = (assetPriceBTC * (answer.toUint256())) /
            10**10;
        uint256 usdvPriceInUSDT = (_amount * tokenPrice) / 10**6;
        uint256 value = (usdvPriceInUSDT * 10**6) / heavenUSDTPrice;
        uint256 ownerTax = (value * exchange_2_TreasuryFeePercent) /
            BASIS_POINTS;
        uint256 LPTax = (value * exchange_2_LPFeePercent) / BASIS_POINTS;
        if (value > (ownerTax + LPTax)) {
            _burn(msg.sender, _amount);

            require(
                HeavenToken.transfer(treasuryWallet, (ownerTax)),
                "Transfer Problem 5"
            );

            require(
                HeavenToken.transfer(msg.sender, (value - ownerTax - LPTax)),
                "Transfer Problem 6"
            );
            emit Exchange_2_Event(
                msg.sender,
                _amount,
                assetPriceBTC,
                heavenUSDTPrice,
                tokenPrice,
                usdvPriceInUSDT,
                (value - ownerTax - LPTax),
                answer
            );
        }
    }

    function getChainlinkDataFeedLatestAnswer(bool BtcOrEth)
        public
        view
        whenNotPaused
        returns (int256 answerReturn, uint256 timeStamp)
    {
        if (BtcOrEth) {
            (
                uint80 roundId,
                int256 answer,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = dataFeedBtc.latestRoundData();
            require(answeredInRound >= roundId, "Stale price");
            require(answer > 0, "Chainlink answer reporting 0");

            answerReturn = answer;
            timeStamp = updatedAt;
        } else {
            (
                uint80 roundId,
                int256 answer,
                ,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = dataFeedEth.latestRoundData();

            require(answeredInRound >= roundId, "Stale price");
            require(answer > 0, "Chainlink answer reporting 0");

            answerReturn = answer;
            timeStamp = updatedAt;
        }
    }

    function updateBurnFee(uint256 _newBurnFee) external onlyOwner {
        require(_newBurnFee < 1000000, "Limit Problem");
        burnFee = _newBurnFee;
    }

    function updateMinBurnFee(uint256 _newMinBurnFee) external onlyOwner {
        require(_newMinBurnFee < 2000000, "Limit Problem");
        minBurnAmount = _newMinBurnFee;
    }

    function changeAggregatorBTC(address _aggr) external onlyOwner {
        dataFeedBtc = AggregatorV3Interface(_aggr);
    }

    function changeAggregatorETH(address _aggr) external onlyOwner {
        dataFeedEth = AggregatorV3Interface(_aggr);
    }

    function updateCheckINFrequency(uint256 _newFrequency) external onlyOwner {
        checkINFrequency = _newFrequency;
    }

    function updateEarnRate(uint256 _newRate) external onlyOwner {
        checkINEarnRate = _newRate;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function setPhoenix(address _contractAddress) external onlyOwner {
        PhoenixToken = ISlayer(payable(_contractAddress));
    }

    function setHeaven(address _contractAddress) external onlyOwner {
        HeavenToken = ISlayer(payable(_contractAddress));
    }

    function updatePrice(uint256 _newPrice) external onlyOwner {
        tokenPrice = _newPrice;
    }

    function updateWhiteList(address _address, bool _newStatus)
        external
        onlyOwner
    {
        require(_address != address(0), "Problem");
        whiteListed[_address] = _newStatus;
    }

    function updateTreasuryWallet(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Problem");
        treasuryWallet = _newAddress;
    }

    function updateMintFeePercent(uint256 _newFee) external onlyOwner {
        require(_newFee < 500, "Limit Problem");
        mintFeePercent = _newFee;
    }

    function updateExchange_1_FeePercent(
        uint256 _newOwnerFee,
        uint256 _newLPFee
    ) external onlyOwner {
        exchange_1_TreasuryFeePercent = _newOwnerFee;
        exchange_1_LPFeePercent = _newLPFee;
    }

    function updateExchange_2_FeePercent(
        uint256 _newOwnerFee,
        uint256 _newLPFee
    ) external onlyOwner {
        exchange_2_TreasuryFeePercent = _newOwnerFee;
        exchange_2_LPFeePercent = _newLPFee;
    }

    function updateIsPublicMintOpen(bool _newStatus) external onlyOwner {
        isPublicMintOpen = _newStatus;
    }

    function updateIsPublicRedeemOpen(bool _newStatus) external onlyOwner {
        isPublicRedeemOpen = _newStatus;
    }

    function updateMinusMint(uint256 _newMinus) external onlyOwner {
        require(_newMinus < 2000000, "Limit Problem");
        minusMint = _newMinus;
    }

    function updateIsClaimOpen(bool _newStatus) external onlyOwner {
        isClaimOpen = _newStatus;
    }

    function updateIsCheckINOpen(bool _newStatus) external onlyOwner {
        isCheckINOpen = _newStatus;
    }

    function updateIsExchange_1_Open(bool _newStatus) external onlyOwner {
        isExchange_1_Open = _newStatus;
    }

    function updateIsExchange_2_Open(bool _newStatus) external onlyOwner {
        isExchange_2_Open = _newStatus;
    }

    function withdrawFundsERC20(address erc20, uint256 amount)
        external
        onlyOwner
    {
        if (IERC20Extented(erc20).balanceOf(address(this)) >= amount) {
            IERC20Extented(erc20).transfer(msg.sender, amount);
        }
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        uint256 amount = value;
        if (from != address(0) && to != address(0) && from != address(this)) {
            if (value > burnFee) {
                if (value > minBurnAmount) {
                    _burn(msg.sender, burnFee);
                    amount = amount - burnFee;
                }
            } else {}
        }

        super._update(from, to, amount);
    }
}
