pragma solidity >= 0.8.13;

contract CollatzDeployer {
    function deployExploiterContract() public returns(address contractAddress) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x6026600c60003960206000f36004356002810660105760011c6017565b600302)

            mstore(add(ptr, 0x20), 0x6001015b60005260206000f30000000000000000000000000000000000000000)

            contractAddress := create(0, ptr, 44)
        }
    }
}