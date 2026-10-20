package com.householdhelper.app.ui.list

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.CatalogItem
import com.householdhelper.app.ui.exposeTestTags
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

private const val NEW_SHOP = "__new__"

/**
 * The add flow (floating +): product with typing hints from the household's products, size/quantity,
 * and a shop dropdown that can create a shop on the spot. Products are not tied to shops.
 */
@Composable
fun AddItemSheet(container: AppContainer, scope: CoroutineScope, onDismiss: () -> Unit) {
    // `scope` belongs to the screen: the sheet is gone (and its own scope cancelled) before the
    // network calls finish.
    val shops by container.list.shops.collectAsStateWithLifecycle()
    val products by container.list.products.collectAsStateWithLifecycle()
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var name by remember { mutableStateOf("") }
    var quantity by remember { mutableStateOf("") }
    var shopSelection by remember { mutableStateOf("") }   // "" = not sure yet, shop id, or NEW_SHOP
    var newShopName by remember { mutableStateOf("") }
    var picked by remember { mutableStateOf<CatalogItem?>(null) }
    var shopMenu by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val trimmed = name.trim()
    val suggestions = remember(name, products) { container.list.suggestions(name).filter { !it.name.equals(trimmed, ignoreCase = true) } }
    val canSubmit = trimmed.isNotEmpty() && (shopSelection != NEW_SHOP || newShopName.isNotBlank())

    fun pick(p: CatalogItem) {
        name = p.name; picked = p
        if (quantity.isBlank()) quantity = p.defaultUnit ?: ""
        if (shopSelection.isEmpty() && p.shopId != null && shops.any { it.id == p.shopId }) shopSelection = p.shopId
    }

    fun submit() {
        if (!canSubmit) return
        val itemName = trimmed
        val qty = quantity.trim().ifEmpty { null }
        val product = picked?.takeIf { it.name.equals(itemName, ignoreCase = true) }
        val selection = shopSelection
        val shopName = newShopName.trim()
        onDismiss()
        scope.launch {
            val shopId = when (selection) {
                "" -> null
                NEW_SHOP -> container.list.addShop(shopName)?.id
                else -> selection
            }
            container.list.add(itemName, shopId = shopId, catalogItemId = product?.id, quantity = qty)
        }
    }

    LaunchedEffect(Unit) { focus.requestFocus() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state, modifier = Modifier.testTag("list.addSheet").exposeTestTags()) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).imePadding()) {
            Text("Add to the list", style = MaterialTheme.typography.titleLarge)
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = name, onValueChange = { name = it; if (picked != null && !it.equals(picked!!.name, ignoreCase = true)) picked = null },
                label = { Text("Product") }, placeholder = { Text("What ran out?") }, singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { submit() }),
                modifier = Modifier.fillMaxWidth().focusRequester(focus).testTag("list.input"),
            )
            suggestions.forEach { p ->
                ListItem(
                    headlineContent = { Text(p.name) },
                    leadingContent = { Icon(Icons.Outlined.History, null) },
                    trailingContent = p.defaultUnit?.takeIf { it.isNotBlank() }?.let { { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
                    modifier = Modifier.clickable { pick(p) }.testTag("list.suggestion.${p.name}"),
                )
            }
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = quantity, onValueChange = { quantity = it },
                label = { Text("Size / quantity") }, placeholder = { Text("e.g. 2, 1 gal, large pack") }, singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { submit() }),
                modifier = Modifier.fillMaxWidth().testTag("list.quantity"),
            )
            Spacer(Modifier.height(8.dp))
            val shopLabel = when (shopSelection) { "" -> "Not sure yet"; NEW_SHOP -> "New shop…"; else -> shops.firstOrNull { it.id == shopSelection }?.name ?: "Not sure yet" }
            ExposedDropdownMenuBox(expanded = shopMenu, onExpandedChange = { shopMenu = it }, modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = shopLabel, onValueChange = {}, readOnly = true, label = { Text("Shop") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = shopMenu) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).testTag("list.shop"),
                )
                DropdownMenu(expanded = shopMenu, onDismissRequest = { shopMenu = false }, modifier = Modifier.exposedDropdownSize().exposeTestTags()) {
                    DropdownMenuItem(text = { Text("Not sure yet") }, onClick = { shopSelection = ""; shopMenu = false }, modifier = Modifier.testTag("list.shop.none"))
                    shops.forEach { s ->
                        DropdownMenuItem(text = { Text(s.name) }, onClick = { shopSelection = s.id; shopMenu = false }, modifier = Modifier.testTag("list.shop.${s.name}"))
                    }
                    DropdownMenuItem(text = { Text("New shop…") }, leadingIcon = { Icon(Icons.Outlined.Add, null) }, onClick = { shopSelection = NEW_SHOP; shopMenu = false }, modifier = Modifier.testTag("list.shop.new"))
                }
            }
            if (shopSelection == NEW_SHOP) {
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(value = newShopName, onValueChange = { newShopName = it }, label = { Text("Shop name") }, singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { submit() }),
                    modifier = Modifier.fillMaxWidth().testTag("list.newShop"))
            }
            Spacer(Modifier.height(16.dp))
            Button(onClick = { submit() }, enabled = canSubmit, shapes = ButtonDefaults.shapes(), modifier = Modifier.fillMaxWidth().height(52.dp).testTag("list.submit")) {
                Text("Add to the list")
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
