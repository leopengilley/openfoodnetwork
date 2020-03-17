# frozen_string_literal: true

class TruncateData
  # This model lets us operate on the sessions DB table using ActiveRecord's
  # methods within the scope of this service. This relies on the AR's
  # convention where a Session model maps to a sessions table.
  class Session < ActiveRecord::Base
  end

  def initialize(months_to_keep = nil)
    @date = (months_to_keep || 3).to_i.months.ago
  end

  def call
    logging do
      truncate_inventory
      truncate_adjustments
      truncate_order_associations
      truncate_order_cycle_data

      sql_delete_from "spree_orders #{where_oc_id_in_ocs_to_delete}"

      truncate_subscriptions

      sql_delete_from "order_cycles #{where_ocs_to_delete}"

      Spree::TokenizedPermission.where("created_at < '#{date}'").delete_all

      remove_transient_data
    end
  end

  private

  attr_reader :date

  def logging
    Rails.logger.info("TruncateData started with truncation date #{date}")
    yield
    Rails.logger.info("TruncateData finished")
  end

  def truncate_order_associations
    sql_delete_from "spree_line_items #{where_order_id_in_orders_to_delete}"
    sql_delete_from "spree_payments #{where_order_id_in_orders_to_delete}"
    sql_delete_from "spree_shipments #{where_order_id_in_orders_to_delete}"
    sql_delete_from "spree_return_authorizations #{where_order_id_in_orders_to_delete}"
  end

  def remove_transient_data
    Spree::StateChange.delete_all("created_at < '#{1.month.ago.to_date}'")
    Spree::LogEntry.delete_all("created_at < '#{1.month.ago.to_date}'")
    Session.delete_all("created_at < '#{2.weeks.ago.to_date}'")
  end

  def truncate_subscriptions
    sql_delete_from "order_cycle_schedules #{where_oc_id_in_ocs_to_delete}"
    sql_delete_from "proxy_orders #{where_oc_id_in_ocs_to_delete}"
  end

  def truncate_inventory
    sql_delete_from "
        spree_inventory_units #{where_order_id_in_orders_to_delete}"
    sql_delete_from "
        spree_inventory_units
        where shipment_id in (select id from spree_shipments #{where_order_id_in_orders_to_delete})"
  end

  def sql_delete_from(sql)
    ActiveRecord::Base.connection.execute("DELETE FROM #{sql}")
  end

  def where_order_id_in_orders_to_delete
    "where order_id in (select id from spree_orders #{where_oc_id_in_ocs_to_delete})"
  end

  def where_oc_id_in_ocs_to_delete
    "where order_cycle_id in (select id from order_cycles #{where_ocs_to_delete} )"
  end

  def where_ocs_to_delete
    "where orders_close_at < '#{date}'"
  end

  def truncate_adjustments
    sql_delete_from "spree_adjustments where source_type = 'Spree::Order'
      and source_id in (select id from spree_orders #{where_oc_id_in_ocs_to_delete})"

    sql_delete_from "spree_adjustments where source_type = 'Spree::Shipment'
      and source_id in (select id from spree_shipments #{where_order_id_in_orders_to_delete})"

    sql_delete_from "spree_adjustments where source_type = 'Spree::Payment'
      and source_id in (select id from spree_payments #{where_order_id_in_orders_to_delete})"

    sql_delete_from "spree_adjustments where source_type = 'Spree::LineItem'
      and source_id in (select id from spree_line_items #{where_order_id_in_orders_to_delete})"
  end

  def truncate_order_cycle_data
    sql_delete_from "coordinator_fees #{where_oc_id_in_ocs_to_delete}"
    sql_delete_from "
    exchange_variants where exchange_id
    in (select id from exchanges #{where_oc_id_in_ocs_to_delete})"
    sql_delete_from "
        exchange_fees where exchange_id
        in (select id from exchanges #{where_oc_id_in_ocs_to_delete})"
    sql_delete_from "exchanges #{where_oc_id_in_ocs_to_delete}"
  end
end
