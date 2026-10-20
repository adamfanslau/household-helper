package com.householdhelper.app.ui.shops

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.material3.SwipeToDismissBoxDefaults
import androidx.compose.material3.SwipeToDismissBoxState
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ShoppingCartCheckout
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.height
import com.householdhelper.app.ui.CheckMark
import com.householdhelper.app.ui.Chip
import com.householdhelper.app.ui.EmptyState
import com.householdhelper.app.ui.ProgressCapsule
import com.householdhelper.app.ui.ShopGlyph
import com.householdhelper.app.ui.theme.Brand
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import com.householdhelper.app.ui.exposeTestTags
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.Shop
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItemDefaults
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import com.householdhelper.app.data.ShoppingListItem
import com.householdhelper.app.ui.SparkGlyph

@Serializable
data object ShopsList : NavKey

@Serializable
data class ShopDetail(val shopId: String) : NavKey

/** Shops tab: Navigation 3 back stack (list → detail), deep links push a detail entry. */
@Composable
fun ShopsScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val backStack = rememberNavBackStack(ShopsList)
    val openShopId by container.router.openShopId.collectAsStateWithLifecycle()
    LaunchedEffect(openShopId) {
        val id = openShopId ?: return@LaunchedEffect
        if (backStack.lastOrNull() != ShopDetail(id)) { backStack.clear(); backStack.add(ShopsList); backStack.add(ShopDetail(id)) }
        container.router.openShopId.value = null
    }
    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        modifier = modifier,
        entryProvider = entryProvider {
            entry<ShopsList> { ShopsListScreen(container, onOpen = { backStack.add(ShopDetail(it.id)) }) }
            entry<ShopDetail> { key -> ShopDetailScreen(container, key.shopId, onBack = { backStack.removeLastOrNull() }) }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun ShopsListScreen(container: AppContainer, onOpen: (Shop) -> Unit) {
    val scope = rememberCoroutineScope()
    val allShops by container.list.shops.collectAsStateWithLifecycle()
    val items by container.list.items.collectAsStateWithLifecycle()
    val shops = remember(allShops, items) { com.householdhelper.app.data.ListRepository.Counts.byActivity(allShops, items) }
    var draft by remember { mutableStateOf("") }
    var pendingDelete by remember { mutableStateOf<Shop?>(null) }

    fun add() { val n = draft.trim(); if (n.isEmpty()) return; draft = ""; scope.launch { container.list.addShop(n) } }

    Scaffold(
        topBar = {
            TopAppBar(title = {
                Column {
                    Text("Shops")
                    if (shops.isNotEmpty()) Text("Most to buy first", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            })
        },
        bottomBar = {
            Surface(tonalElevation = 3.dp, modifier = Modifier.imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(draft, { draft = it }, placeholder = { Text("Add a shop") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { add() }),
                        modifier = Modifier.weight(1f).testTag("shops.input"))
                    Spacer(Modifier.width(8.dp))
                    FilledIconButton(onClick = { add() }, enabled = draft.isNotBlank(), shapes = IconButtonDefaults.shapes(), modifier = Modifier.testTag("shops.add")) {
                        Icon(Icons.Outlined.Add, contentDescription = "Add shop")
                    }
                }
            }
        },
    ) { padding ->
        if (shops.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                EmptyState(Icons.Outlined.Storefront, "No shops yet", "Add the places you shop. Items you add for a shop are grouped under it, with a count of what is left to buy.")
            }
        } else LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            items(shops, key = { it.id }) { shop ->
                val state = rememberSwipeToDismissBoxState(confirmValueChange = { v -> if (v == SwipeToDismissBoxValue.EndToStart) { pendingDelete = shop }; false })
                SwipeToDismissBox(
                    state = state, enableDismissFromStartToEnd = false, modifier = Modifier.animateItem(),
                    backgroundContent = {
                        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                            Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.onErrorContainer)
                        }
                    },
                ) {
                    val open = com.householdhelper.app.data.ListRepository.Counts.openCount(items, shop.id)
                    val basket = items.count { it.shopId == shop.id && it.isInBasket }
                    val tint = Brand.shopColor(shop.name)
                    ListItem(
                        headlineContent = { Text(shop.name, style = MaterialTheme.typography.titleMedium) },
                        supportingContent = {
                            Column {
                                Text(
                                    when { open == 0 -> "Nothing to buy"; basket > 0 -> "$basket of $open in the basket"; else -> "$open to buy" },
                                    style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                if (open > 0) ProgressCapsule(basket.toFloat() / open, tint, Modifier.padding(top = 6.dp, end = 8.dp))
                            }
                        },
                        leadingContent = { ShopGlyph(shop.name, size = 44.dp) },
                        trailingContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (open > 0) Surface(shape = MaterialTheme.shapes.extraLarge, color = tint.copy(alpha = 0.16f)) {
                                    Text("$open", style = MaterialTheme.typography.labelLarge, color = tint,
                                        modifier = Modifier.padding(horizontal = 11.dp, vertical = 4.dp).testTag("shops.count.${shop.name}"))
                                }
                                Spacer(Modifier.width(8.dp))
                                Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.outline)
                            }
                        },
                        modifier = Modifier.clickable { onOpen(shop) }
                            .semantics(mergeDescendants = true) { contentDescription = "${shop.name}, ${com.householdhelper.app.data.ListRepository.Counts.openCount(items, shop.id)} to buy" }
                            .testTag("shops.row.${shop.name}"),
                    )
                }
            }
            item(key = "order-note") {
                // Why the order moves: a dark brand card with the spark.
                Surface(
                    shape = RoundedCornerShape(20.dp),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp).semantics(mergeDescendants = true) {},
                ) {
                    Row(
                        Modifier.background(Brush.linearGradient(listOf(Brand.Ink, Brand.InkSoft))).padding(horizontal = 18.dp, vertical = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SparkGlyph(size = 22.dp, tint = Brand.MintBright)
                        Spacer(Modifier.width(14.dp))
                        Column {
                            Text("Shopping order follows you", style = MaterialTheme.typography.titleSmall, color = Color.White)
                            Text("Shops with the most left to buy rise to the top, so the next errand is always first.",
                                style = MaterialTheme.typography.bodySmall, color = Color.White.copy(alpha = 0.78f))
                        }
                    }
                }
            }
        }
    }
    pendingDelete?.let { shop ->
        AlertDialog(
            modifier = Modifier.exposeTestTags(),
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete ${shop.name}?") },
            text = { Text("Items on the list move to Unsorted; your products keep their history.") },
            confirmButton = { TextButton(onClick = { pendingDelete = null; scope.launch { container.list.deleteShop(shop) } }, modifier = Modifier.testTag("shops.delete.confirm")) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Cancel") } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ShopDetailScreen(container: AppContainer, shopId: String, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val shops by container.list.shops.collectAsStateWithLifecycle()
    val items by container.list.items.collectAsStateWithLifecycle()
    val shop = shops.firstOrNull { it.id == shopId }
    val needed = remember(items) { items.filter { it.shopId == shopId && !it.isBought }.let { l -> l.filter { !it.isInBasket } + l.filter { it.isInBasket } } }
    val toFind = needed.filter { !it.isInBasket }
    val inBasket = needed.filter { it.isInBasket }
    val basket = inBasket.size
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(shop?.name ?: "Shop") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back") } },
                actions = {
                    IconButton(onClick = { menu = true }, modifier = Modifier.testTag("shop.menu")) { Icon(Icons.Outlined.Storefront, contentDescription = "Shop menu") }
                    androidx.compose.material3.DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.exposeTestTags()) {
                        androidx.compose.material3.DropdownMenuItem(text = { Text("Rename") }, onClick = { menu = false; newName = shop?.name ?: ""; renaming = true })
                        androidx.compose.material3.DropdownMenuItem(text = { Text("Delete shop", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; confirmDelete = true })
                    }
                },
            )
        },
        bottomBar = {
            if (basket > 0) Surface(tonalElevation = 3.dp) {
                Button(
                    onClick = { haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.Confirm); scope.launch { container.list.checkout(shopId) } },
                    shapes = ButtonDefaults.shapes(),
                    colors = ButtonDefaults.buttonColors(containerColor = Brand.Basket, contentColor = Color.White),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp).height(52.dp).testTag("shop.checkout"),
                ) {
                    Icon(Icons.Outlined.ShoppingCartCheckout, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Checkout · $basket in the basket")
                }
            }
        },
    ) { padding ->
        val tint = Brand.shopColor(shop?.name ?: "")
        val header: @Composable () -> Unit = {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                ShopGlyph(shop?.name, size = 56.dp)
                Spacer(Modifier.width(16.dp))
                Column(Modifier.weight(1f)) {
                    Text(shop?.name ?: "Shop", style = MaterialTheme.typography.headlineSmall)
                    Text(
                        when { needed.isEmpty() -> "All done here"; basket > 0 -> "$basket of ${needed.size} in the basket · ${toFind.size} left to find"; else -> "${needed.size} to buy" },
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Box(contentAlignment = Alignment.Center) {
                    androidx.compose.material3.CircularProgressIndicator(
                        progress = { if (needed.isEmpty()) 1f else basket.toFloat() / needed.size },
                        color = tint, trackColor = tint.copy(alpha = 0.18f), strokeWidth = 6.dp, gapSize = 0.dp,
                        modifier = Modifier.size(52.dp),
                    )
                    Text(if (needed.isEmpty()) "✓" else "$basket/${needed.size}", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        if (needed.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(padding)) {
                header()
                Spacer(Modifier.height(24.dp))
                EmptyState(Brand.shopIcon(shop?.name ?: ""), "Nothing to buy here", "Items you add for ${shop?.name ?: "this shop"} show up here, ready to tick off in the aisle.")
            }
        } else LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(bottom = 16.dp)) {
            item(key = "header") { header() }
            // The aisle is two piles: what is still to find on top, what is already in the basket below.
            fun LazyListScope.pile(label: String, rows: List<ShoppingListItem>) {
                if (rows.isEmpty()) return
                item(key = "label-$label") {
                    Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 20.dp, top = 14.dp, bottom = 6.dp).testTag("shop.section.$label"))
                }
                itemsIndexed(rows, key = { _, it -> it.id }) { index, item ->
                    val first = index == 0; val last = index == rows.lastIndex
                    val shape = RoundedCornerShape(topStart = if (first) 20.dp else 0.dp, topEnd = if (first) 20.dp else 0.dp, bottomStart = if (last) 20.dp else 0.dp, bottomEnd = if (last) 20.dp else 0.dp)
                    Column(Modifier.animateItem().padding(horizontal = 16.dp).clip(shape).background(MaterialTheme.colorScheme.surfaceContainerLowest)) {
                        ListItem(
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            headlineContent = { Text(item.name, color = if (item.isInBasket) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface) },
                            supportingContent = item.quantity?.takeIf { it.isNotBlank() }?.let { { Chip(it, tint, Modifier.padding(top = 3.dp)) } },
                            leadingContent = { CheckMark(item.status, tint) },
                            trailingContent = if (item.isInBasket) null else { { Text("Tap to tick", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline) } },
                            modifier = Modifier.clickable { haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.ToggleOn); scope.launch { container.list.toggle(item) } }
                                .semantics(mergeDescendants = true) { contentDescription = "${item.name}${item.quantity?.let { ", $it" } ?: ""}, ${if (item.isInBasket) "in basket" else "needed"}" }
                                .testTag("shop.row.${item.name}"),
                        )
                        if (!last) HorizontalDivider(Modifier.padding(start = 60.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                    }
                }
            }
            pile("Still to find", toFind)
            pile("In the basket", inBasket)
        }
    }
    if (renaming) AlertDialog(
        modifier = Modifier.exposeTestTags(),
        onDismissRequest = { renaming = false }, title = { Text("Rename shop") },
        text = { OutlinedTextField(newName, { newName = it }, singleLine = true, modifier = Modifier.testTag("shop.rename.input")) },
        confirmButton = { TextButton(onClick = { renaming = false; shop?.let { s -> scope.launch { container.list.renameShop(s, newName) } } }) { Text("Save") } },
        dismissButton = { TextButton(onClick = { renaming = false }) { Text("Cancel") } },
    )
    if (confirmDelete) AlertDialog(
        modifier = Modifier.exposeTestTags(),
        onDismissRequest = { confirmDelete = false }, title = { Text("Delete ${shop?.name ?: "shop"}?") },
        text = { Text("Items on the list move to Unsorted; your products keep their history.") },
        confirmButton = { TextButton(onClick = { confirmDelete = false; shop?.let { s -> scope.launch { container.list.deleteShop(s) }; onBack() } }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
}
