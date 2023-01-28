# [Collatz Puzzle](https://quillctf.super.site/challenges/quillctf-challenges/collatz-puzzle)

[QuillHash](https://audits.quillhash.com/) has a really fun [Capture-the-Flag (CTF) series](https://quillctf.super.site/) going right now for EVM-based challenges. One called [Collatz Puzzle](https://quillctf.super.site/challenges/quillctf-challenges/collatz-puzzle) in particular requires some low-level EVM work that I couldn't find great resources for elsewhere, so am recording those learnings as they apply to the CTF here.

This piece will demonstrate how to write logic in opcodes and how to use Assembly to deploy that logic on-chain.

**Note**: Before we get started, I can't recommend the site [evm.codes](https://www.evm.codes/) enough. It was instrumental in debugging and stepping through opcode-based logic, and I almost certainly would have given up on this challenge without it.

## Identifying the Problem to Solve
The success criteria for this CTF reads:
> Make a successful call to the callMe function.

The challenge code is below for reference:

```
contract CollatzPuzzle is ICollatz {
  function collatzIteration(uint256 n) public pure override returns (uint256) {
    if (n % 2 == 0) {
      return n / 2;
    } else {
      return 3 * n + 1;
    }
  }

  function callMe(address addr) external view returns (bool) {
    // check code size
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }
    require(size > 0 && size <= 32, "bad code size!");

    // check results to be matching
    uint p;
    uint q;
    for (uint256 n = 1; n < 200; n++) {
      // local result
      p = n;
      for (uint256 i = 0; i < 5; i++) {
        p = collatzIteration(p);
      }
      // your result
      q = n;
      for (uint256 i = 0; i < 5; i++) {
        q = ICollatz(addr).collatzIteration{gas: 100}(q);
      }
      require(p == q, "result mismatch!");
    }

    return true;
  }
}
```

So the very first step, before writing any code, is to understand the conditions under which a call to that function would be successful. The `require` statements are your best friend here. There are two of them, suggesting there are two checks that the code must pass during execution.

The first is that the codesize has to be less than 32 bytes (`require(size > 0 && size <= 32, "bad code size!");`), and the second is that the the values `p` and `q` must match (`require(p == q, "result mismatch!");`).

The first requirement is conceptually straightforward - the code needs to be small. 

The second requires some more analysis to understand the action we need to take. Diving deeper into the `for` loop where `p` and `q` get compared, we see that `p` is calculated using the `collatzIteration` function, while `q` is calculated by making a call out to `ICollatz(addr).collatzIteration(q)` **and** takes less than 100 gas. Practically, this means that the contract at `addr` needs to contain logic that will return the same value that `collatzIteration` would, given the same input.

**Note**: The experienced Solidity dev might think to use [`delegatecall`](https://www.evm.codes/#f4?fork=merge) to deploy a contract of minimal size that calls more complex logic elsewhere. However, the gas limit of 100 defined in the **CollatzPuzzle** code makes that approach infeasible, as `delegateCall` takes 100 gas on its own.

To summarize, at this point we know we have to:
1. Write code that mimics the logic of the function `collatzIteration`,
2. that is 32 bytes or less in size,
3. deployed as a smart contract

## Encoding logic into opcodes
Right off the bat, we know 32 bytes is too small to deploy with standard Solidity, or even Yul. And so, writing in opcodes is the right tool for the job. Recall the `collatzIteration` functionality: for any even value of _n_, return _n / 2_. For odd values, return _(3 * n) + 1_. We also know that the call will be coming from an external contract, which means there will need to be an element of loading calldata into memory as well.

To summarize, the basic flow looks something like this:
* Load calldata
* Determine if calldata value is even or odd
    * If even, divide by 2
    * If odd, multiply by 3 and add 1
* Return value produced by above logic

After some trial and error, we arrive at one possible solution:

```
0x6004356002810660105760011c6017565b6003026001015b60005260206000f3 // 32 bytes exactly
```

The explanations for what each of those opcodes do are in the table below.


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

A better formatted version of the above table is [here](https://docs.google.com/spreadsheets/d/1wZfKqSQhd4MhuV87g5jiMxf6KNCnYNlSNCbnX1ssr-A/edit?usp=sharing).

With this bytestring, we have fulfilled requirements (1) and (2) of mimicking the logic of `collatzIteration` in 32 bytes or less. The next step is deploying it, making it callable by **CollatzPuzzle**.

## Deploying Bytecode
The next hurdle is deploying the code on-chain. Due to the construction of the EVM, it is not as easy as copy/pasting the raw code into an address, though - more opcodes and Assembly are required to deploy the code we want. 

One such solution for doing so is below.

```
0x6026600c60003960206000f3 // 12 bytes
```

With accompanying explanations:

|Name    |Gas|Code|Argument|Function                                                 |Effect                                     |
|--------|---|----|--------|---------------------------------------------------------|-------------------------------------------|
|PUSH    |3  |60  |26      |Length of code to copy                                   |Push only desired bytecode to memory       |
|PUSH    |3  |60  |0c      |Offset of source code                                    |                                           |
|PUSH    |3  |60  |00      |Offset in destination memory                             |                                           |
|CODECOPY|3  |39  |        |Use previous 3 stack items to copy bytecode to memory    |                                           |
|        |   |    |        |                                                         |                                           |
|PUSH    |3  |60  |20      |Length in memory to return                               |Return bytecode in memory as smart contract|
|PUSH    |3  |60  |00      |Offset in memory to return                               |                                           |
|RETURN  |   |f3  |        |Use previous 2 stack items to return bytecode as contract|                                           |


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

The secret sauce in these deployment instructions is the `CODECOPY` opcode, which copies a portion of the code in the current execution context into memory. Because of the `create` function, the only thing in the execution context is the code at memory location `ptr` ~ `ptr + 44`, or the deployment code + our `collatzIteration` bytecode. 

Essentially we are saying "copy 0x26 (32) bytes of code from the bytestring `0x6026600c60003960206000f36004356002810660105760011c6017565b6003026001015b60005260206000f3`, starting at location 0x0c (12)". The opcodes afterwards set up the correct code to be returned, which results in the creation of the smart contract at address `contractAddress`.

## Testing
To test, I deployed assembly above within a function called `deployExploiterContract()`, which returns the address that contains the bytecode. I passed that in as the argument to **collatzPuzzle.callMe(address)** and it returned true.

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