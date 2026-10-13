package com.householdhelper.app.ui.list

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.ListItem
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.ListGrouping
import com.householdhelper.app.data.ShoppingListItem
import com.householdhelper.app.ui.settings.shareInvite
import kotlinx.coroutines.launch

/** The home screen: needed items grouped by shop, Unsorted last, Recently bought, add bar above the keyboard. */
@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun ListScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val household by container.households.current.collectAsStateWithLifecycle()
    val items by container.list.items.collectAsStateWithLifecycle()
    val shops by container.list.shops.collectAsStateWithLifecycle()
    val loading by container.list.loading.collectAsStateWithLifecycle()
    val error by container.list.error.collectAsStateWithLifecycle()
    val pending by container.list.pendingDeletes.collectAsStateWithLifecycle()
    val invites by container.households.invites.collectAsStateWithLifecycle()
    var showBought by remember { mutableStateOf(false) }
    var draft by remember { mutableStateOf("") }
    var sheetItem by remember { mutableStateOf<ShoppingListItem?>(null) }
    var editing by remember { mutableStateOf<ShoppingListItem?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }

    LaunchedEffect(household?.id) { household?.let { container.list.load(it.id) } }
    LaunchedEffect(error) { error?.let { snackbar.showSnackbar(it); container.list.error.value = null } }
    LaunchedEffect(pending.lastOrNull()?.item?.id) {
        val p = pending.lastOrNull() ?: return@LaunchedEffect
        val result = snackbar.showSnackbar("Deleted ${p.item.name}", actionLabel = "Undo", duration = SnackbarDuration.Indefinite) // cancelled with the grace period
        if (result == SnackbarResult.ActionPerformed) container.list.undoDelete(p.item.id)
    }

    val sections = remember(items, shops) { ListGrouping.sections(items, shops) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val code = invites.firstOrNull { it.revokedAt == null }?.code

    fun submit() {
        val name = draft.trim(); if (name.isEmpty()) return
        draft = ""
        scope.launch { container.list.add(name) }
    }

    Scaffold(
        modifier = modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Shopping")
                        Text(household?.name ?: "", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                actions = {
                    if (code != null) {
                        IconButton(onClick = { shareInvite(context, code, household?.name ?: "") }, modifier = Modifier.testTag("list.share")) {
                            Icon(Icons.Outlined.Share, contentDescription = "Share invite")
                        }
                    }
                },
                scrollBehavior = scrollBehavior,
            )
        },
        snackbarHost = { SnackbarHost(snackbar, Modifier.testTag("snackbar")) },
        bottomBar = {
            // Add bar pinned above the keyboard (imePadding) and the navigation bar.
            Surface(tonalElevation = 3.dp, modifier = Modifier.imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = draft, onValueChange = { draft = it },
                        placeholder = { Text("Add something we ran out of…") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { submit() }),
                        modifier = Modifier.weight(1f).testTag("list.input"),
                    )
                    Spacer(Modifier.width(8.dp))
                    FilledIconButton(onClick = { submit() }, enabled = draft.isNotBlank(), shapes = IconButtonDefaults.shapes(), modifier = Modifier.testTag("list.add")) {
                        Icon(Icons.Outlined.Add, contentDescription = "Add item")
                    }
                }
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = { scope.launch { refreshing = true; container.list.refresh(); refreshing = false } },
            modifier = Modifier.fillMaxSize().padding(padding),
            state = rememberPullToRefreshState(),
            indicator = { PullToRefreshDefaults.LoadingIndicator(state = rememberPullToRefreshState(), isRefreshing = refreshing, modifier = Modifier.align(Alignment.TopCenter)) },
        ) {
            when {
                loading && items.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { LoadingIndicator() }
                sections.isEmpty -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.ShoppingCart, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text("Nothing to buy", style = MaterialTheme.typography.titleMedium, modifier = Modifier.testTag("list.empty"))
                        Text("Add items as they run out at home.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                else -> LazyColumn(Modifier.fillMaxSize().testTag("list"), contentPadding = PaddingValues(bottom = 24.dp)) {
                    sections.needed.forEach { section ->
                        stickyHeader(key = "h-${section.id}") {
                            Surface(color = MaterialTheme.colorScheme.surface) {
                                Text(
                                    "${section.title} · ${section.items.size}",
                                    style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp).testTag("list.section.${section.title}"),
                                )
                            }
                        }
                        items(section.items, key = { it.id }) { item ->
                            SwipeRow(
                                item = item,
                                onBought = { haptics.performHapticFeedback(HapticFeedbackType.ToggleOn); scope.launch { container.list.toggle(item) } },
                                onDelete = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); container.list.delete(item) },
                                modifier = Modifier.animateItem(),
                            ) {
                                ItemRow(item, container.list.shop(item.shopId)?.name,
                                    onClick = { haptics.performHapticFeedback(HapticFeedbackType.ToggleOn); scope.launch { container.list.toggle(item) } },
                                    onLongClick = { sheetItem = item }, meUid = container.auth.uid)
                            }
                        }
                        if (section.shopId == null) item(key = "f-unsorted") {
                            Text("Long-press an item to assign a shop.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 16.dp, top = 4.dp))
                        }
                    }
                    if (sections.bought.isNotEmpty()) {
                        item(key = "h-bought") {
                            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                                TextButton(onClick = { showBought = !showBought }, modifier = Modifier.testTag("list.bought.toggle")) {
                                    Text("Recently bought (${sections.bought.size}) ${if (showBought) "▾" else "▸"}", style = MaterialTheme.typography.titleSmall)
                                }
                                Spacer(Modifier.weight(1f))
                                var menu by remember { mutableStateOf(false) }
                                IconButton(onClick = { menu = true }, modifier = Modifier.testTag("list.bought.menu")) { Icon(Icons.Outlined.MoreVert, contentDescription = "More") }
                                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.exposeTestTags()) {
                                    DropdownMenuItem(text = { Text("Clear recently bought") }, leadingIcon = { Icon(Icons.Outlined.Delete, null) },
                                        onClick = { menu = false; scope.launch { container.list.clearBought() } }, modifier = Modifier.testTag("list.bought.clear"))
                                }
                            }
                        }
                        if (showBought) items(sections.bought, key = { it.id }) { item ->
                            SwipeRow(item, onBought = { scope.launch { container.list.toggle(item) } }, onDelete = { container.list.delete(item) }, modifier = Modifier.animateItem()) {
                                ItemRow(item, container.list.shop(item.shopId)?.name, onClick = { scope.launch { container.list.toggle(item) } }, onLongClick = { sheetItem = item }, meUid = container.auth.uid)
                            }
                        }
                    }
                }
            }
        }
    }

    sheetItem?.let { item ->
        val sheetState = rememberModalBottomSheetState()
        ModalBottomSheet(onDismissRequest = { sheetItem = null }, sheetState = sheetState, modifier = Modifier.testTag("item.sheet").exposeTestTags()) {
            Text(item.name, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            Text("Move to shop", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp))
            shops.forEach { shop ->
                ListItem(
                    headlineContent = { Text(shop.name) },
                    leadingContent = { Icon(Icons.Outlined.Storefront, null) },
                    trailingContent = { if (shop.id == item.shopId) Text("current", style = MaterialTheme.typography.labelMedium) },
                    modifier = Modifier.combinedClickable(enabled = shop.id != item.shopId) { sheetItem = null; scope.launch { container.list.move(item, shop.id) } }
                        .testTag("item.move.${shop.name}"),
                )
            }
            ListItem(headlineContent = { Text("Unsorted") }, modifier = Modifier.combinedClickable(enabled = item.shopId != null) { sheetItem = null; scope.launch { container.list.move(item, null) } }.testTag("item.move.Unsorted"))
            ListItem(headlineContent = { Text("Edit") }, leadingContent = { Icon(Icons.Outlined.Edit, null) }, modifier = Modifier.combinedClickable { sheetItem = null; editing = item }.testTag("item.edit"))
            ListItem(headlineContent = { Text(if (item.isBought) "Mark needed" else "Mark bought") }, leadingContent = { Icon(Icons.Outlined.CheckCircle, null) },
                modifier = Modifier.combinedClickable { sheetItem = null; scope.launch { container.list.toggle(item) } }.testTag("item.toggle"))
            ListItem(headlineContent = { Text("Delete", color = MaterialTheme.colorScheme.error) }, leadingContent = { Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error) },
                modifier = Modifier.combinedClickable { sheetItem = null; container.list.delete(item) }.testTag("item.delete"))
            Spacer(Modifier.padding(16.dp))
        }
    }

    editing?.let { item ->
        var name by remember(item.id) { mutableStateOf(item.name) }
        var quantity by remember(item.id) { mutableStateOf(item.quantity ?: "") }
        AlertDialog(
            modifier = Modifier.exposeTestTags(),
            onDismissRequest = { editing = null },
            title = { Text("Edit item") },
            text = {
                Column {
                    OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.testTag("edit.name"))
                    Spacer(Modifier.padding(4.dp))
                    OutlinedTextField(quantity, { quantity = it }, label = { Text("Quantity (optional)") }, singleLine = true, modifier = Modifier.testTag("edit.quantity"))
                }
            },
            confirmButton = { TextButton(onClick = { editing = null; scope.launch { container.list.edit(item, name, quantity) } }, enabled = name.isNotBlank(), modifier = Modifier.testTag("edit.save")) { Text("Save") } },
            dismissButton = { TextButton(onClick = { editing = null }) { Text("Cancel") } },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeRow(item: ShoppingListItem, onBought: () -> Unit, onDelete: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val bought by rememberUpdatedState(onBought)
    val delete by rememberUpdatedState(onDelete)
    val density = LocalDensity.current
    val threshold = SwipeToDismissBoxDefaults.positionalThreshold
    // Not rememberSaveable: LazyColumn restores saved state per key, so a row brought back by Undo
    // would inherit its dismissed state and stop responding to swipes.
    val state = remember(item.id) {
        SwipeToDismissBoxState(SwipeToDismissBoxValue.Settled, density, confirmValueChange = { value ->
            when (value) {
                SwipeToDismissBoxValue.StartToEnd -> { bought(); false }  // bought / un-buy; row stays
                SwipeToDismissBoxValue.EndToStart -> { delete(); true }
                else -> false
            }
        }, positionalThreshold = threshold)
    }
    SwipeToDismissBox(
        state = state,
        modifier = modifier,
        backgroundContent = {
            val toEnd = state.dismissDirection == SwipeToDismissBoxValue.StartToEnd
            Box(
                Modifier.fillMaxSize().background(if (toEnd) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp),
                contentAlignment = if (toEnd) Alignment.CenterStart else Alignment.CenterEnd,
            ) {
                Icon(if (toEnd) Icons.Outlined.CheckCircle else Icons.Outlined.Delete, contentDescription = if (toEnd) "Bought" else "Delete",
                    tint = if (toEnd) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onErrorContainer)
            }
        },
    ) {
        Surface(color = MaterialTheme.colorScheme.surface) { content() }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ItemRow(item: ShoppingListItem, shopName: String?, onClick: () -> Unit, onLongClick: () -> Unit, meUid: String? = null) {
    val desc = buildList {
        add(item.name)
        item.quantity?.takeIf { it.isNotBlank() }?.let { add(it) }
        add(if (item.isBought) "bought" else "needed")
        shopName?.let { add(it) }
    }.joinToString(", ")
    // "added by" only for other members; display names arrive with step 10, dev uids are readable as-is.
    val addedBy = item.addedBy?.takeIf { it != meUid && it.startsWith("dev-") }?.removePrefix("dev-")?.replaceFirstChar { it.uppercase() }
    Row(
        Modifier.fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .semantics(mergeDescendants = true) { contentDescription = desc }
            .testTag("list.item.${item.name}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (item.isBought) Icons.Outlined.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (item.isBought) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(16.dp))
        Column {
            Text(
                item.name,
                style = MaterialTheme.typography.bodyLarge,
                textDecoration = if (item.isBought) TextDecoration.LineThrough else null,
                color = if (item.isBought) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
            val sub = listOfNotNull(item.quantity?.takeIf { it.isNotBlank() }, addedBy?.let { "added by $it" }).joinToString(" · ")
            if (sub.isNotEmpty()) Text(sub, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
