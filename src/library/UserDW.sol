// SPDX -License-Identifier: MIT

pragma solidity ^0.8.23;

library UserDW {
    struct Withdraw {
        uint256[2] pA;
        uint256[2][2] pB;
        uint256[2] pC;
        bytes32 nullifierHash;
        address receiver;
        bytes32 root;
        uint256 fee;
        address relayer;
        uint256 amount;
        bool withdraw;
        bytes32 commitment;
        bool depositW;
        address senderPool;
    }
}
