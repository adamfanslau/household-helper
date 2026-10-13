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
    val shops by container.list.shops.collectAsStateWithLifecycle()
    var draft by remember { mutableStateOf("") }
    var pendingDelete by remember { mutableStateOf<Shop?>(null) }

    fun add() { val n = draft.trim(); if (n.isEmpty()) return; draft = ""; scope.launch { container.list.addShop(n) } }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Shops") }) },
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
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.Storefront, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("No shops yet", style = MaterialTheme.typography.titleMedium)
                    Text("Add the places you shop; items can then be grouped by shop.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
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
                    ListItem(
                        headlineContent = { Text(shop.name) },
                        leadingContent = { Icon(Icons.Outlined.Storefront, null) },
                        trailingContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (shop.neededCount > 0) Badge { Text("${shop.neededCount}") }
                                Spacer(Modifier.width(8.dp))
                                Icon(Icons.Outlined.ChevronRight, null)
                            }
                        },
                        modifier = Modifier.clickable { onOpen(shop) }
                            .semantics(mergeDescendants = true) { contentDescription = "${shop.name}, ${shop.neededCount} needed" }
                            .testTag("shops.row.${shop.name}"),
                    )
                }
            }
        }
    }
    pendingDelete?.let { shop ->
        AlertDialog(
            modifier = Modifier.exposeTestTags(),
            onDismissRequest = { pendingDelete = null },
            title = { Text("Delete ${shop.name}?") },
            text = { Text("Its catalog is removed. Items on the list move to Unsorted.") },
            confirmButton = { TextButton(onClick = { pendingDelete = null; scope.launch { container.list.deleteShop(shop) } }, modifier = Modifier.testTag("shops.delete.confirm")) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Cancel") } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ShopDetailScreen(container: AppContainer, shopId: String, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    val household by container.households.current.collectAsStateWithLifecycle()
    val shops by container.list.shops.collectAsStateWithLifecycle()
    val shop = shops.firstOrNull { it.id == shopId }
    val catalog = remember(household?.id, shopId) { household?.let { com.householdhelper.app.data.CatalogRepository(container.api, it.id, shopId) } }
    val items by (catalog?.items ?: kotlinx.coroutines.flow.MutableStateFlow(emptyList())).collectAsStateWithLifecycle()
    val loaded by (catalog?.loaded ?: kotlinx.coroutines.flow.MutableStateFlow(false)).collectAsStateWithLifecycle()
    val eventsState by container.events.state.collectAsStateWithLifecycle()
    val pending by (catalog?.pendingDeletes ?: kotlinx.coroutines.flow.MutableStateFlow(emptyList())).collectAsStateWithLifecycle()
    val catalogError by (catalog?.error ?: kotlinx.coroutines.flow.MutableStateFlow<String?>(null)).collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    var draft by remember { mutableStateOf("") }
    var added by remember { mutableStateOf(setOf<String>()) }
    var menu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }

    LaunchedEffect(catalog) { catalog?.load() }
    LaunchedEffect(eventsState) { if (eventsState == com.householdhelper.app.data.EventsClient.State.CONNECTED) catalog?.load() }
    LaunchedEffect(catalogError) { catalogError?.let { snackbar.showSnackbar(it); catalog?.error?.value = null } }
    LaunchedEffect(pending.lastOrNull()?.item?.id) {
        val p = pending.lastOrNull() ?: return@LaunchedEffect
        val result = snackbar.showSnackbar("Deleted ${p.item.name}", actionLabel = "Undo", duration = SnackbarDuration.Indefinite) // cancelled with the grace period
        if (result == SnackbarResult.ActionPerformed) catalog?.undoDelete(p.item.id)
    }

    fun add() { val n = draft.trim(); if (n.isEmpty()) return; draft = ""; scope.launch { catalog?.add(n) } }

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
            Surface(tonalElevation = 3.dp, modifier = Modifier.imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(draft, { draft = it }, placeholder = { Text("Add an item this shop sells") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { add() }),
                        modifier = Modifier.weight(1f).testTag("shop.input"))
                    Spacer(Modifier.width(8.dp))
                    FilledIconButton(onClick = { add() }, enabled = draft.isNotBlank(), shapes = IconButtonDefaults.shapes(), modifier = Modifier.testTag("shop.add")) {
                        Icon(Icons.Outlined.Add, contentDescription = "Add catalog item")
                    }
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbar, modifier = Modifier.testTag("snackbar")) },
    ) { padding ->
        if (loaded && items.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No items for this shop yet", style = MaterialTheme.typography.titleMedium)
                    Text("Add the things you usually buy here.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } else LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            items(items, key = { it.id }) { item ->
                val isAdded = item.id in added
                val current by rememberUpdatedState(item)
                val density = LocalDensity.current
                val threshold = SwipeToDismissBoxDefaults.positionalThreshold
                // Not rememberSaveable: a row restored by Undo must not inherit its dismissed state (see ListScreen.SwipeRow).
                val state = remember(item.id) {
                    SwipeToDismissBoxState(SwipeToDismissBoxValue.Settled, density, confirmValueChange = { v -> if (v == SwipeToDismissBoxValue.EndToStart) { catalog?.delete(current); true } else false }, positionalThreshold = threshold)
                }
                SwipeToDismissBox(
                    state = state, enableDismissFromStartToEnd = false, modifier = Modifier.animateItem(),
                    backgroundContent = {
                        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp), contentAlignment = Alignment.CenterEnd) {
                            Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = MaterialTheme.colorScheme.onErrorContainer)
                        }
                    },
                ) {
                    ListItem(
                        headlineContent = { Text(item.name) },
                        supportingContent = item.defaultUnit?.takeIf { it.isNotBlank() }?.let { { Text(it) } },
                        trailingContent = {
                            Surface(shape = MaterialTheme.shapes.extraLarge, color = if (isAdded) MaterialTheme.colorScheme.tertiaryContainer else MaterialTheme.colorScheme.primaryContainer) {
                                Text(if (isAdded) "✓ Added" else "+ To list", style = MaterialTheme.typography.labelLarge,
                                    color = if (isAdded) MaterialTheme.colorScheme.onTertiaryContainer else MaterialTheme.colorScheme.onPrimaryContainer,
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                            }
                        },
                        modifier = Modifier.clickable(enabled = !isAdded) {
                            added = added + item.id
                            scope.launch {
                                container.list.add(item.name, shopId = shopId, catalogItemId = item.id)
                                kotlinx.coroutines.delay(1500)
                                added = added - item.id
                            }
                        }.semantics(mergeDescendants = true) { contentDescription = "${item.name}, add to list" }.testTag("shop.toList.${item.name}"),
                    )
                }
            }
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
        text = { Text("Its catalog is removed. Items on the list move to Unsorted.") },
        confirmButton = { TextButton(onClick = { confirmDelete = false; shop?.let { s -> scope.launch { container.list.deleteShop(s) }; onBack() } }) { Text("Delete", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
}
