// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract ReentrancyGuard {
    bool internal locked;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

library SafeERC20 {
    function safeTransfer(IERC20 token, address to, uint value) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(IERC20 token, address spender, uint value) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(isContract(address(token)), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(
                abi.decode(returndata, (bool)),
                "SafeERC20: ERC20 operation did not succeed"
            );
        }
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}

contract SmartGarage is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address private TokenAddress = 0x55d398326f99059fF775485246999027B3197955;
    IERC20 public Token;

    uint256[] public REFERRAL_PERCENTS = [4, 3, 2, 1];
    uint256[] public GARAGE_PROFIT_PERCENTAGE = [210, 220, 230, 240, 250, 260];
    uint256[] public GARAGE_ENTER_LIMIT = [0, 0, 0, 0, 50_000 ether, 100_000 ether];
    uint256 public MIN_BUY_AMOUNT = 5 ether;
    uint256 public REFERRAL_STEP = 10;
    uint256 public ADMIN_FEE = 800;
    uint256 public MARKEING_FEE = 200;
    uint256 public REFERRAL_PROFIT_STEP = 100;
    uint256 public MAX_REFERRAL_PROFIT_STEP = 1000;
    uint256 public MAX_GARAGE_PROFIT = 23000;
    uint8 public MAX_GARAGE_COUNT = 6;
    uint256 public constant MAX_PROFIT_LIMIT = 1 days;
    uint256 public constant PERCENTS_DIVIDER = 10000;
    uint256 public constant TIME_STEP = 1 days;

    struct Garage {
        uint256 tools;
        uint256 cash;
        uint256 cash2;
        uint256 timestamp;
        address ref;
        uint256 DirectReferral;
        uint256 totalBuy;
        uint256[4] referralProfit;
        uint8[6] cars;
        uint256[6] garageBuyAmount;
        uint256[6] profitEarned;
    }

    mapping(address => Garage) public garages;
    uint256 public totalCars;
    uint256 public totalGarage;
    uint256 public totalBuy;
    uint256 public totalConvert;
    address public manager;
    address public adminWallet;
    address public marketingWallet;
    uint256 public startDate;

    constructor() {
        Token = IERC20(TokenAddress);
        manager = 0x12Fbef4CF5134666D74877697D18Ea08C747D272;
        adminWallet = 0xEF7d920B05D3f0b3a0151440a5b1D7a84F2E6f42;
        marketingWallet = 0x12D19080f19aBd7Eeaf6A9371AEe2d1EE47170Be;
        startDate = 1702922400;
    }

    function buyTools(address ref, uint256 amount) public noReentrant {
        require(block.timestamp >= startDate, "contract does not launch yet");
        uint256 tools = amount;
        require(tools >= MIN_BUY_AMOUNT, "Minimum 5 USDT");

        uint256 adminFee = (amount * ADMIN_FEE) / PERCENTS_DIVIDER;
        uint256 marketingFee = (amount * MARKEING_FEE) / PERCENTS_DIVIDER;

        Token.safeTransferFrom(msg.sender, adminWallet, adminFee);
        Token.safeTransferFrom(msg.sender, marketingWallet, marketingFee);
        Token.safeTransferFrom(
            msg.sender,
            address(this),
            amount - (adminFee + marketingFee)
        );

        address user = msg.sender;

        if (garages[user].timestamp == 0) {
            totalGarage++;
            ref = garages[ref].timestamp == 0 ? manager : ref;
            garages[ref].DirectReferral++;
            garages[user].ref = ref;
            garages[user].timestamp = block.timestamp;
        }

        ref = garages[user].ref;
        if (ref != address(0)) {
            address upline = ref;
            for (uint256 i = 0; i < REFERRAL_PERCENTS.length; i++) {
                if (upline != address(0)) {
                    uint256 commission = (tools * REFERRAL_PERCENTS[i]) / 100;
                    garages[upline].tools += (commission / 2);
                    garages[upline].cash += ((commission / 2) * 100);
                    garages[upline].referralProfit[i] += commission;
                    upline = garages[upline].ref;
                } else break;
            }
        }

        garages[user].tools += tools;
        garages[user].totalBuy += tools;
        totalBuy += amount;
    }

    function withdrawCash() public noReentrant {
        address user = msg.sender;
        uint256 cash = garages[user].cash;
        garages[user].cash = 0;
        uint256 amount = cash / 100;
        Token.safeTransfer(
            msg.sender,
            getContractBalance() < amount ? getContractBalance() : amount
        );
    }

    function convertCash(uint256 _cashAmount) public noReentrant {
        address user = msg.sender;
        uint256 cash = garages[user].cash;
        require(cash >= _cashAmount, "Not enough cash");
        garages[user].cash -= _cashAmount;
        uint256 amount = _cashAmount / 100;
        garages[user].tools += amount;
        totalConvert += amount;
    }

    function collectCash() public noReentrant {
        address user = msg.sender;
        syncGarage(user);
        garages[user].cash += garages[user].cash2;
        garages[user].cash2 = 0;
    }

    function upgradeGarage(uint256 garageId) public noReentrant {
        require(garageId < MAX_GARAGE_COUNT, "Max 6 garage");
        require(totalBuy >= GARAGE_ENTER_LIMIT[garageId], "Not enough total buy amount");
        address user = msg.sender;
        syncGarage(user);
        garages[user].cars[garageId]++;
        totalCars++;
        uint256 carLevel = garages[user].cars[garageId];
        garages[user].garageBuyAmount[garageId] += getUpgradePrice(
            garageId,
            carLevel
        );
        require(
            garages[user].tools >= getUpgradePrice(garageId, carLevel),
            "Not enough tools"
        );
        garages[user].tools -= getUpgradePrice(garageId, carLevel);
    }

    function getCars(address addr) public view returns (uint8[6] memory) {
        return garages[addr].cars;
    }

    function getCommission(
        address addr
    ) public view returns (uint256[4] memory) {
        return garages[addr].referralProfit;
    }

    function getGarageBuyAmount(
        address addr
    ) public view returns (uint256[6] memory) {
        return garages[addr].garageBuyAmount;
    }

    function syncGarage(address user) internal {
        require(garages[user].timestamp > 0, "User is not registered");
        uint256 duration = block.timestamp - garages[user].timestamp;
        if (duration > MAX_PROFIT_LIMIT) {
            duration = MAX_PROFIT_LIMIT;
        }
        uint256 totalProfit;
        for (uint256 i = 0; i < MAX_GARAGE_COUNT; i++) {
            if (garages[user].garageBuyAmount[i] > 0) {
                uint256 profitPercentage = GARAGE_PROFIT_PERCENTAGE[i] +
                    ((GARAGE_PROFIT_PERCENTAGE[i] * getLeadershipBonus(user)) /
                        PERCENTS_DIVIDER);
                uint256 profitAmount = (garages[user].garageBuyAmount[i] *
                    profitPercentage) / PERCENTS_DIVIDER;
                    profitAmount = (profitAmount * duration) / TIME_STEP;
                uint256 maxGarageProfit = garages[user].garageBuyAmount[i] * MAX_GARAGE_PROFIT / PERCENTS_DIVIDER;
                if(garages[user].profitEarned[i] + profitAmount >= maxGarageProfit){
                    profitAmount = maxGarageProfit - garages[user].profitEarned[i];
                    garages[user].cars[i] = 0;
                    garages[user].profitEarned[i] = 0;
                    garages[user].garageBuyAmount[i] = 0;
                }else{
                    garages[user].profitEarned[i] += profitAmount;
                }
                totalProfit += profitAmount;
            }
        }
        garages[user].cash2 += totalProfit * 100;
        garages[user].timestamp = block.timestamp;
    }

    function getUpgradePrice(
        uint256 garageId,
        uint256 carLevel
    ) internal pure returns (uint256) {
        if (carLevel == 1)
            return
                [
                    5 ether,
                    50 ether,
                    100 ether,
                    500 ether,
                    1000 ether,
                    5000 ether
                ][garageId];
        if (carLevel == 2)
            return
                [
                    10 ether,
                    60 ether,
                    150 ether,
                    600 ether,
                    1500 ether,
                    6000 ether
                ][garageId];
        if (carLevel == 3)
            return
                [
                    15 ether,
                    70 ether,
                    200 ether,
                    700 ether,
                    2000 ether,
                    7000 ether
                ][garageId];
        if (carLevel == 4)
            return
                [
                    20 ether,
                    80 ether,
                    250 ether,
                    800 ether,
                    2500 ether,
                    8000 ether
                ][garageId];
        revert("Incorrect car level");
    }

    function getDailyProfit(
        address user
    ) public view returns (uint256 totalProfit) {
        if (garages[user].timestamp == 0) {
            return 0;
        }
        uint256 duration = TIME_STEP;
        for (uint256 i = 0; i < MAX_GARAGE_COUNT; i++) {
            if (garages[user].garageBuyAmount[i] > 0) {
                uint256 profitPercentage = GARAGE_PROFIT_PERCENTAGE[i] +
                    ((GARAGE_PROFIT_PERCENTAGE[i] * getLeadershipBonus(user)) /
                        PERCENTS_DIVIDER);
                uint256 profitAmount = (garages[user].garageBuyAmount[i] *
                    profitPercentage) / PERCENTS_DIVIDER;
                uint256 maxGarageProfit = garages[user].garageBuyAmount[i] * MAX_GARAGE_PROFIT / PERCENTS_DIVIDER;
                if(garages[user].profitEarned[i] + profitAmount >= maxGarageProfit){
                    profitAmount = maxGarageProfit - garages[user].profitEarned[i];
                }
                totalProfit += ((profitAmount * duration) / TIME_STEP) * 100;
            }
        }
    }

    function getGaragesPercentage(
        address user
    ) public view returns (uint256[6] memory percentages) {
        if (garages[user].timestamp == 0) {
            return percentages;
        }
        uint256 duration = block.timestamp - garages[user].timestamp;
        if (duration > MAX_PROFIT_LIMIT) {
            duration = MAX_PROFIT_LIMIT;
        }
        for (uint256 i = 0; i < MAX_GARAGE_COUNT; i++) {
            if (garages[user].garageBuyAmount[i] > 0) {
                uint256 profitPercentage = GARAGE_PROFIT_PERCENTAGE[i] +
                    ((GARAGE_PROFIT_PERCENTAGE[i] * getLeadershipBonus(user)) /
                        PERCENTS_DIVIDER);
                uint256 profitAmount = (garages[user].garageBuyAmount[i] *
                    profitPercentage) / PERCENTS_DIVIDER;
                    profitAmount = ((profitAmount * duration) / TIME_STEP);
                uint256 maxGarageProfit = garages[user].garageBuyAmount[i] * MAX_GARAGE_PROFIT / PERCENTS_DIVIDER;
                if(garages[user].profitEarned[i] + profitAmount >= maxGarageProfit){
                    percentages[i] = 10000;
                }
                else{
                    percentages[i] = ((garages[user].profitEarned[i] + profitAmount) * 10000 / maxGarageProfit) * MAX_GARAGE_PROFIT / PERCENTS_DIVIDER;
                }
            }
        }
        return percentages;
    }

    function getUpgradeProfit(
        uint256 garageId,
        uint256 carLevel
    ) public view returns (uint256 totalProfit) {
        uint256 upgradePrice = getUpgradePrice(garageId, carLevel);
        uint256 profitAmount = (upgradePrice *
            GARAGE_PROFIT_PERCENTAGE[garageId]) / PERCENTS_DIVIDER;
        totalProfit = ((profitAmount * TIME_STEP) / TIME_STEP) * 100;
    }

    function getUserAvailableCash(
        address user
    ) public view returns (uint256 totalProfit) {
        if (garages[user].timestamp == 0) {
            return 0;
        }
        uint256 duration = block.timestamp - garages[user].timestamp;
        if (duration > MAX_PROFIT_LIMIT) {
            duration = MAX_PROFIT_LIMIT;
        }
        for (uint256 i = 0; i < MAX_GARAGE_COUNT; i++) {
            if (garages[user].garageBuyAmount[i] > 0) {
                uint256 profitPercentage = GARAGE_PROFIT_PERCENTAGE[i] +
                    ((GARAGE_PROFIT_PERCENTAGE[i] * getLeadershipBonus(user)) /
                        PERCENTS_DIVIDER);
                uint256 profitAmount = (garages[user].garageBuyAmount[i] *
                    profitPercentage) / PERCENTS_DIVIDER;
                    profitAmount = ((profitAmount * duration) / TIME_STEP);
                uint256 maxGarageProfit = garages[user].garageBuyAmount[i] * MAX_GARAGE_PROFIT / PERCENTS_DIVIDER;
                if(garages[user].profitEarned[i] + profitAmount >= maxGarageProfit){
                    profitAmount = maxGarageProfit - garages[user].profitEarned[i];
                }
                totalProfit += profitAmount * 100;
            }
        }
    }

    function getLeadershipBonus(address user) public view returns (uint256) {
        uint256 referralStep = garages[user].DirectReferral / REFERRAL_STEP;
        uint256 referralProfit = referralStep * REFERRAL_PROFIT_STEP;
        if (referralProfit > MAX_REFERRAL_PROFIT_STEP) {
            referralProfit = MAX_REFERRAL_PROFIT_STEP;
        }
        return referralProfit;
    }

    function getContractBalance() public view returns (uint256) {
        return Token.balanceOf(address(this));
    }
}
