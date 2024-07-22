# res://scenes/battle/InventoryMenu.gd
extends Control

signal item_selected(item)

@onready var item_list = $ItemList
@onready var use_button = $UseButton
@onready var cancel_button = $CancelButton
@onready var currency_label = $CurrencyLabel  # Add this line

var current_inventory: Inventory

func _ready():
	hide()
	use_button.connect("pressed", Callable(self, "_on_use_pressed"))
	cancel_button.connect("pressed", Callable(self, "_on_cancel_pressed"))
	item_list.connect("item_selected", Callable(self, "_on_item_selected"))

func show_inventory(inventory: Inventory, currency: Currency):
	current_inventory = inventory
	refresh_item_list()
	update_currency_display(currency)
	show()

func refresh_item_list():
	item_list.clear()
	for item_id in current_inventory.items:
		var item_data = current_inventory.items[item_id]
		var item_name = item_data.item.name if item_data.item else "Unknown Item"
		var quantity = item_data.quantity
		var display_text = "%s (x%d)" % [item_name, quantity]
		item_list.add_item(display_text)
		print("Added to item list: %s" % display_text)

func update_currency_display(currency: Currency):
	currency_label.text = "Currency: %s" % currency.get_formatted()

func _on_use_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_name = current_inventory.items.keys()[item_index]
		var item = current_inventory.items[item_name].item
		emit_signal("item_selected", item)
		hide()

func _on_cancel_pressed():
	hide()

func _on_item_selected(_index):
	use_button.disabled = false
