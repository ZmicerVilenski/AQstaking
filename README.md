# Staking (exponential reward)

![STAKING](./img.png)

---

## ! node.js needed !

node-gyp?

## Install

```shell
npm i
```

## Compile

```shell
npx hardhat compile
```

## Deploy

```shell
npx hardhat run scripts/deploy.js
```

```shell
npx hardhat node
npx hardhat run scripts/deploy.js --network localhost
```

## Unit tests

```shell
npx hardhat test
REPORT_GAS=true npx hardhat test
```

---

# Deploy in mainnet or testnetworks

1. Fill all keys in .env file
2. Deploy

```shell
npx hardhat run scripts/deploy.js --network [rinkeby/ropsten/mainnet]
```

3. Verify

```shell
npx hardhat verify --network [rinkeby/ropsten/mainnet] DEPLOYED_CONTRACT_ADDRESS "Token address"
exmpl: npx hardhat verify --network ropsten 0x9c7aF68C72c3994eAD71035c4E8b3D9C4365734f "0x3c77B6965eF3a3C6E91e38c179e24Cbbc9dd4fE9"
```
