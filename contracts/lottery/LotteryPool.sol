// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// import "../pool/interfaces/IPool.sol";

// contract LotteryPool is Ownable {
//     IPool public immutable pool;
//     uint256 public immutable lockPeriod; // 1 week | 2 weeks | 1 month | 3 months| 6 months | 1 year;

//     struct Instance {
//         uint id;
//         uint256 start;
//         uint256 end;
//         uint256 ticketPrice;
//         uint256 winner;
//         uint256 prize;
//     }

//     mapping(uint => EnumerableSet.AddressSet) internal _participants;
//     mapping(uint256 => Instance) internal _instances;
//     uint internal _currentInstanceId;
//     uint256 internal _latestInstanceId;

//     constructor(IPool pool_, uint256 lockPeriod_) {
//         pool = pool_;
//         lockPeriod = lockPeriod_;
//     }

//     function createInstance(Instance memory instance) public {
//         require(instance.start > _instances[_latestInstanceId].end, "CREATE: New instance cannot start until previous ends");
//         _latestInstanceId += 1;
//         instance.id = _latestInstanceId;
//         instance.end = instance.start + lockPeriod;
//         _instances[_latestInstanceId] = instance;
//         // emit NewInstance();
//     }

//     function join
// }
