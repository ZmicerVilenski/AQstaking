# Aqualis Staking

![STAKING](./img.png)

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
npx hardhat run scripts/deploy.ts --network localhost
```

## Unit tests

```shell
npx hardhat test
REPORT_GAS=true npx hardhat test
```
