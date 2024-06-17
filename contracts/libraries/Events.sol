// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Events {
  // Emitted when the sell and buy tax fees are updated
  event TaxChanged(uint8 newSellTax, uint8 newBuyTax);

  // Emitted when a user is blacklisted
  event UserBanned(address user);

  // Emitted when a user is unbanned
  event UserUnbanned(address user);

  // Emitted when a new auction is created
  event AuctionCreated(
    address seller,
    address priceToken,
    address nftAddress,
    uint256 tokenId,
    uint256 floorPrice,
    uint256 startAuction,
    uint256 endAuction,
    uint256 erc1155Quantity,
    uint256 bidIncrement
  );

  // Emitted when a bid is placed on an auction
  event BidPlaced(uint256 auctionId, address bidder, uint256 bidAmount);

  // Emitted when a bid is withdrawn from an auction
  event BidWithdrawn(uint256 auctionId, address bidder, uint256 withdrawalAmount);

  // Emitted when an auction ends
  event AuctionEnded(uint256 auctionId, address winner, uint256 finalPrice);

  // Emitted when an auction is withdrawn (no bids placed)
  event AuctionWithdrawn(uint256 auctionId);

  // Emitted when a new sale listing is created
  event SaleCreated(
    address seller,
    address paymentToken,
    address nftAddress,
    uint256 tokenId,
    uint256 price,
    uint256 erc1155Quantity
  );

  // Emitted when an NFT is sold from a sale listing
  event SaleCompleted(
    uint256 saleId,
    address buyer,
    address seller,
    address nftAddress,
    uint256 tokenId,
    uint256 price
  );

  // Emitted when a sale listing is cancelled
  event SaleCanceled(uint256 saleId);

  // Emitted when a user withdraws funds
  event Withdrawal(address user, address tokenAddress, uint256 amount);
}