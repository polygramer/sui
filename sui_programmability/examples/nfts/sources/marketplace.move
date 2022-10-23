// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module nfts::marketplace {
    use sui::dynamic_field;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::coin::{Self, Coin};

    // For when amount paid does not match the expected.
    const EAmountIncorrect: u64 = 0;

    // For when someone tries to delist without ownership.
    const ENotOwner: u64 = 1;

    struct Marketplace has key {
        id: UID,
    }

    /// A single listing which contains the listed item and its price in [`Coin<C>`].
    struct Listing<T: key + store, phantom C> has store {
        item: T,
        ask: u64, // Coin<C>
        owner: address,
    }

    /// Create a new shared Marketplace.
    public entry fun create(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let marketplace = Marketplace { id };
        transfer::share_object(marketplace);
    }

    /// List an item at the Marketplace.
    public entry fun list<T: key + store, C>(
        marketplace: &mut Marketplace,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let item_id = object::id(&item);
        let listing = Listing<T, C> {
            item,
            ask,
            owner: tx_context::sender(ctx),
        };
        dynamic_field::add(&mut marketplace.id, item_id, listing);
    }

    /// Remove listing and get an item back. Only owner can do that.
    public fun delist<T: key + store, C>(
        marketplace: &mut Marketplace,
        item_id: ID,
        ctx: &mut TxContext
    ): T {
        let Listing<T, C> { item, ask: _, owner } =
            dynamic_field::remove(&mut marketplace.id, item_id);

        assert!(tx_context::sender(ctx) == owner, ENotOwner);

        item
    }

    /// Call [`delist`] and transfer item to the sender.
    public entry fun delist_and_take<T: key + store, C>(
        marketplace: &mut Marketplace,
        item_id: ID,
        ctx: &mut TxContext
    ) {
        let item = delist<T, C>(marketplace, item_id, ctx);
        transfer::transfer(item, tx_context::sender(ctx));
    }

    /// Purchase an item using a known Listing. Payment is done in Coin<C>.
    /// Amount paid must match the requested amount. If conditions are met,
    /// owner of the item gets the payment and buyer receives their item.
    public fun buy<T: key + store, C>(
        marketplace: &mut Marketplace,
        item_id: ID,
        paid: Coin<C>,
    ): T {
        let Listing<T, C> { item, ask, owner } =
            dynamic_field::remove(&mut marketplace.id, item_id);

        assert!(ask == coin::value(&paid), EAmountIncorrect);

        transfer::transfer(paid, owner);
        item
    }

    /// Call [`buy`] and transfer item to the sender.
    public entry fun buy_and_take<T: key + store, C>(
        marketplace: &mut Marketplace,
        item_id: ID,
        paid: Coin<C>,
        ctx: &mut TxContext
    ) {
        transfer::transfer(buy<T, C>(marketplace, item_id, paid), tx_context::sender(ctx))
    }
}

#[test_only]
module nfts::marketplaceTests {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario::{Self, Scenario};
    // use nfts::bag::{Self, Bag};
    use nfts::marketplace;

    // Simple Kitty-NFT data structure.
    struct Kitty has key, store {
        id: UID,
        kitty_id: u8
    }

    const ADMIN: address = @0xA55;
    const SELLER: address = @0x00A;
    const BUYER: address = @0x00B;

    /// Create a shared [`Marketplace`].
    fun create_marketplace(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        marketplace::create(test_scenario::ctx(scenario));
    }

    /// Mint SUI and send it to BUYER.
    fun mint_some_coin(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
        transfer::transfer(coin, BUYER);
    }

    /// Mint Kitty NFT and send it to SELLER.
    fun mint_kitty(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, ADMIN);
        let nft = Kitty { id: object::new(test_scenario::ctx(scenario)), kitty_id: 1 };
        transfer::transfer(nft, SELLER);
    }

    // TODO(dyn-child) redo test with dynamic child object loading
    // // SELLER lists Kitty at the Marketplace for 100 SUI.
    // fun list_kitty(scenario: &mut Scenario) {
    //     test_scenario::next_tx(scenario, SELLER);
    //     let mkp_val = test_scenario::take_shared<Marketplace>(scenario);
    //     let mkp = &mut mkp_val;
    //     let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
    //     let nft = test_scenario::take_from_sender<Kitty>(scenario);

    //     marketplace::list<Kitty, SUI>(mkp, &mut bag, nft, 100, test_scenario::ctx(scenario));
    //     test_scenario::return_shared(mkp_val);
    //     test_scenario::return_to_sender(scenario, bag);
    // }

    // TODO(dyn-child) redo test with dynamic child object loading
    // #[test]
    // fun list_and_delist() {
    //     let scenario = &mut test_scenario::begin(ADMIN);

    //     create_marketplace(scenario);
    //     mint_kitty(scenario);
    //     list_kitty(scenario);

    //     test_scenario::next_tx(scenario, SELLER);
    //     {
    //         let mkp_val = test_scenario::take_shared<Marketplace>(scenario);
    //         let mkp = &mut mkp_val;
    //         let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
    //         let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

    //         // Do the delist operation on a Marketplace.
    //         let nft = marketplace::delist<Kitty, SUI>(mkp, &mut bag, listing, test_scenario::ctx(scenario));
    //         let kitty_id = burn_kitty(nft);

    //         assert!(kitty_id == 1, 0);

    //         test_scenario::return_shared(mkp_val);
    //         test_scenario::return_to_sender(scenario, bag);
    //     };
    // }

    // TODO(dyn-child) redo test with dynamic child object loading
    // #[test]
    // #[expected_failure(abort_code = 1)]
    // fun fail_to_delist() {
    //     let scenario = &mut test_scenario::begin(ADMIN);

    //     create_marketplace(scenario);
    //     mint_some_coin(scenario);
    //     mint_kitty(scenario);
    //     list_kitty(scenario);

    //     // BUYER attempts to delist Kitty and he has no right to do so. :(
    //     test_scenario::next_tx(scenario, BUYER);
    //     {
    //         let mkp_val = test_scenario::take_shared<Marketplace>(scenario);
    //         let mkp = &mut mkp_val;
    //         let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
    //         let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

    //         // Do the delist operation on a Marketplace.
    //         let nft = marketplace::delist<Kitty, SUI>(mkp, &mut bag, listing, test_scenario::ctx(scenario));
    //         let _ = burn_kitty(nft);

    //         test_scenario::return_shared(mkp_val);
    //         test_scenario::return_to_sender(scenario, bag);
    //     };
    // }

    // TODO(dyn-child) redo test with dynamic child object loading
    // #[test]
    // fun buy_kitty() {
    //     let scenario = &mut test_scenario::begin(ADMIN);

    //     create_marketplace(scenario);
    //     mint_some_coin(scenario);
    //     mint_kitty(scenario);
    //     list_kitty(scenario);

    //     // BUYER takes 100 SUI from his wallet and purchases Kitty.
    //     test_scenario::next_tx(scenario, BUYER);
    //     {
    //         let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         let mkp_val = test_scenario::take_shared<Marketplace>(scenario);
    //         let mkp = &mut mkp_val;
    //         let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
    //         let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);
    //         let payment = coin::take(coin::balance_mut(&mut coin), 100, test_scenario::ctx(scenario));

    //         // Do the buy call and expect successful purchase.
    //         let nft = marketplace::buy<Kitty, SUI>(&mut bag, listing, payment);
    //         let kitty_id = burn_kitty(nft);

    //         assert!(kitty_id == 1, 0);

    //         test_scenario::return_shared(mkp_val);
    //         test_scenario::return_to_sender(scenario, bag);
    //         test_scenario::return_to_sender(scenario, coin);
    //     };
    // }

    // TODO(dyn-child) redo test with dynamic child object loading
    // #[test]
    // #[expected_failure(abort_code = 0)]
    // fun fail_to_buy() {
    //     let scenario = &mut test_scenario::begin(ADMIN);

    //     create_marketplace(scenario);
    //     mint_some_coin(scenario);
    //     mint_kitty(scenario);
    //     list_kitty(scenario);

    //     // BUYER takes 100 SUI from his wallet and purchases Kitty.
    //     test_scenario::next_tx(scenario, BUYER);
    //     {
    //         let coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         let mkp_val = test_scenario::take_shared<Marketplace>(scenario);
    //         let mkp = &mut mkp_val;
    //         let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
    //         let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

    //         // AMOUNT here is 10 while expected is 100.
    //         let payment = coin::take(coin::balance_mut(&mut coin), 10, test_scenario::ctx(scenario));

    //         // Attempt to buy and expect failure purchase.
    //         let nft = marketplace::buy<Kitty, SUI>(&mut bag, listing, payment);
    //         let _ = burn_kitty(nft);

    //         test_scenario::return_shared(mkp_val);
    //         test_scenario::return_to_sender(scenario, bag);
    //         test_scenario::return_to_sender(scenario, coin);
    //     };
    // }

    fun burn_kitty(kitty: Kitty): u8 {
        let Kitty{ id, kitty_id } = kitty;
        object::delete(id);
        kitty_id
    }
}
