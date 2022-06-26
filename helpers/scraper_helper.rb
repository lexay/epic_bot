module ScraperHelper
  include Hashie::Extensions::DeepFind

  def no_api?
    self[:product_slug].nil?
  end

  def current_and_free?
    promo = self.dig(:promotions, :promotional_offers)
    return false if promo.nil? || promo.empty?

    self.deep_find(:discount_percentage).zero?
  end
end
