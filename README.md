# [Collatz Puzzle](https://quillctf.super.site/challenges/quillctf-challenges/collatz-puzzle)

There are two problems here:
- First is getting opcodes to an address where they can be interacted with - that is a piece for a different time.
- Second is optimizing the math in `collatzIteration` to return the right values. That is what is discussed here.

Use [evm.codes](https://www.evm.codes/)

## Encoding logic into opcodes
The code that needs to be replicated in 32 bytes or less is the following:

```
function collatzIteration(uint256 n) public pure override returns (uint256) {
    if (n % 2 == 0) {
        return n / 2;
    } else {
        return 3 * n + 1;
    }
}
```

Limit of 100 gas means [`delegatecall`](https://www.evm.codes/#f4?fork=merge) is out of the question.
Since we know the call is coming externally, the basic flow is to:
* Load calldata
* Do logic on it
* Return value depending on logic

The opcodes to do so are below:

```
6004356002810660105760011c6017565b6003026001015b60005260206000f3 // 32 bytes exactly
```

The explanations for what those opcodes do are in the below table:


|Name        |Gas|Code|Argument|Function                                 |Effect                                                                          |
|------------|---|----|--------|-----------------------------------------|--------------------------------------------------------------------------------|
|PUSH1       |3  |60  |04      |Calldata load offset                     |n put on top of the stack                                                       |
|CALLDATALOAD|3  |35  |        |Load calldata                            |                                                                                |
|            |   |    |        |                                         |                                                                                |
|PUSH1       |3  |60  |02      |Push modulo divisor                      |See if n is even or odd, 0 on top of stack if even and 1 on top of stack if odd |
|DUP2        |3  |81  |        |Copy calldata and push to numerator      |                                                                                |
|MOD         |5  |06  |        |Modulo                                   |                                                                                |
|            |   |    |        |                                         |                                                                                |
|PUSH1       |3  |60  |10      |Jump location if odd                     |Checking for jumps                                                              |
|JUMPI       |10 |57  |        |Jump to odd logic if the MOD returned `1`|                                                                                |
|            |   |    |        |                                         |                                                                                |
|PUSH        |3  |60  |01      |Bits to shift                            |Logic for completing the even case and jumping to logic for returning the result|
|SHR         |3  |1c  |        |Shift right == divide by 2               |                                                                                |
|PUSH        |3  |60  |17      |Jump location                            |                                                                                |
|JUMP        |8  |56  |        |                                         |                                                                                |
|            |   |    |        |                                         |                                                                                |
|JUMPDEST    |1  |5b  |        |Jump destination                         |Start of division logic                                                         |
|PUSH        |3  |60  |03      |Multiplier                               |Multiplication/addition logic if n is odd                                       |
|MUL         |5  |02  |        |Multiply n by multiplier                 |                                                                                |
|PUSH        |3  |60  |01      |To add                                   |                                                                                |
|ADD         |3  |01  |        |Add multiplied value and 1               |                                                                                |
|            |   |    |        |                                         |                                                                                |
|JUMPDEST    |1  |5b  |        |Jump destination                         |Start of return logic                                                           |
|PUSH        |3  |60  |00      |MSTORE offset                            |Logic for returning the result                                                  |
|MSTORE      |3  |52  |        |Store in memory                          |                                                                                |
|PUSH        |3  |60  |20      |Return size                              |                                                                                |
|PUSH        |3  |60  |00      |Return offset                            |                                                                                |
|RETURN      |0  |f3  |        |Return value                             |                                                                                |

A better formatted version of the above table is [here](https://docs.google.com/spreadsheets/d/1wZfKqSQhd4MhuV87g5jiMxf6KNCnYNlSNCbnX1ssr-A/edit?usp=sharing)

It isn't as easy as copy/pasting raw code into an address, though - some code is also needed to deploy the desired code. That can be acccomplished in 12 bytes:

```
0x6026600c60003960206000f3 // 12 bytes
```

Putting it together, we just need to load the code into contiguous memory and use the `create` function to deploy it.

```
address contractAddress; // used as return value
...
assembly {
    let ptr := mload(0x40)
    mstore(ptr, 0x6026600c60003960206000f36004356002810660105760011c6017565b600302)
    mstore(add(ptr, 0x20), 0x6001015b60005260206000f30000000000000000000000000000000000000000)
    contractAddress := create(0, ptr, 44)
}
```

## Un-optimized code
My first attempt at this code did a 38-byte string, which did not meet the requirements of <=32 bytes. A similar table to the above can be found [here](https://docs.google.com/spreadsheets/d/1wZfKqSQhd4MhuV87g5jiMxf6KNCnYNlSNCbnX1ssr-A/edit#gid=0) explaining how that code worked.

Long code:
```
Opcodes
600435806002900615601a5760030260010160005260206000f35b60011c60005260206000f3 // 38 bytes

Initialization code
6026600c60003960266000f3 // 12 bytes

Combined
0x6026600c60003960266000f3600435806002900615601a5760030260010160005260206000f35b60011c60005260206000f3 // 50 bytes
```

Contract snippet:
```
address contractAddress; // used as return value
...
assembly {
    let ptr := mload(0x40)
    mstore(ptr, 0x6026600c60003960266000f3600435806002900615601a576003026001016000)
    mstore(add(ptr, 0x20), 0x5260206000f35b60011c60005260206000f30000000000000000000000000000)
    contractAddress := create(0, ptr, 50)
}
```