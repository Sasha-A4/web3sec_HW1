# TripFund — сбор на поездку команды

Контракт для сбора взносов в одном ERC-20: до дедлайна участники вносят токены, после срока организатор забирает всю учтенную сумму при достигнутой цели, иначе каждый возвращает свой вклад.

## Версии

| Компонент | Версия |
| --- | --- |
| Foundry (`forge`) | 1.8.x |
| Solidity (`solc`) | 0.8.24 |
| OpenZeppelin Contracts | 5.2.0 |
| OpenZeppelin Foundry Upgrades | 0.4.2 |
| forge-std | 1.17.x |

## Установка

Нужны [Foundry](https://book.getfoundry.sh/getting-started/installation) и Node.js (для проверки хранилища в бонусе V2).

```bash
git clone <url-репозитория>
cd secweb3_hw
git submodule update --init --recursive
npm install
```

## Сборка и тесты

```bash
forge build
forge test
```

Подробный вывод:

```bash
forge test -vvv
```

Только базовая часть без прокси:

```bash
forge test --match-path test/TripFund.t.sol
```

Бонус с Transparent Proxy и V2:

```bash
forge test --match-path test/TripFundUpgrade.t.sol
```

## Пример: approve + взнос

Пользователь сначала дает контракту `TripFund` право списать токены, затем вызывает `contribute`.

В Solidity:

```solidity
token.approve(address(tripFund), amount);
tripFund.contribute(amount);
```

Через `cast` (локальный Anvil):

```bash
# spender — адрес TripFund (в бонусе — адрес прокси)
cast send $TOKEN "approve(address,uint256)" $TRIPFUND 1000000000000000000 --private-key $PK
cast send $TRIPFUND "contribute(uint256)" 1000000000000000000 --private-key $PK
```

Повторные взносы одного адреса суммируются в `contributions(address)` и `totalRaised`.

## Как устроен контракт

Параметры задаются один раз и не меняются:

- `token` — ERC-20 без комиссии и rebasing
- `organizer` — кто забирает сбор при успехе
- `goal` — цель в минимальных единицах токена
- `deadline` — Unix-время; взнос только при `block.timestamp < deadline`

После дедлайна (`block.timestamp >= deadline`):

- если `totalRaised >= goal` — только организатор один раз вызывает `withdraw()` и получает **учтенную** сумму; `totalRaised` не уменьшается
- иначе каждый вызывает `refund()` и получает свой полный вклад; вклад обнуляется до перевода

Прямой `transfer` токена на контракт не меняет `totalRaised` и не выплачивается: после всех положенных выплат эти токены остаются на контракте.

Учет обновляется **до** внешних вызовов (`SafeERC20.safeTransfer` / `safeTransferFrom`). Ошибка перевода откатывает всю операцию.

## Бонус: Transparent Proxy и V2

V1 сразу деплоится через Transparent Proxy OpenZeppelin 5.x. Параметры пишутся в storage в `initialize`. Реализацию напрямую инициализировать нельзя, повторный `initialize` прокси тоже запрещен. Обновляет только владелец `ProxyAdmin`.

В бонусе `approve` вызывается у токена со **spender = адрес прокси**.

До дедлайна прокси обновляется до V2 с `contributeFor(beneficiary, amount)`:

- платит всегда `msg.sender`
- вклад и право на `refund` получает ненулевой `beneficiary`
- взносы суммируются с обычным `contribute`

Проверка совместимости хранилища: `Upgrades.validateUpgrade` в `test/TripFundUpgrade.t.sol`.

## Структура

```
src/
  TripFund.sol       # базовая версия с constructor
  TripFundV1.sol     # upgradeable V1 (initialize)
  TripFundV2.sol     # V2: contributeFor
  TripFundBase.sol   # общая логика
  MockERC20.sol      # тестовый токен
test/
  TripFund.t.sol
  TripFundUpgrade.t.sol
```
