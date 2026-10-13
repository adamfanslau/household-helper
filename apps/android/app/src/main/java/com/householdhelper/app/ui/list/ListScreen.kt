package com.householdhelper.app.ui.list

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.ShoppingCart
import androidx.compose.material3.Icon
import androidx.compose.material3.LoadingIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.householdhelper.app.data.AppContainer
import com.householdhelper.app.data.ListGrouping
import com.householdhelper.app.data.ShoppingListItem

/** Read-only in Android A1: sections per shop in sort order, Unsorted last, Recently bought. */
@Composable
fun ListScreen(container: AppContainer, modifier: Modifier = Modifier) {
    val household by container.households.current.collectAsStateWithLifecycle()
    val items by container.list.items.collectAsStateWithLifecycle()
    val shops by container.list.shops.collectAsStateWithLifecycle()
    val loading by container.list.loading.collectAsStateWithLifecycle()
    var showBought by remember { mutableStateOf(false) }

    LaunchedEffect(household?.id) { household?.let { container.list.load(it.id) } }

    val sections = remember(items, shops) { ListGrouping.sections(items, shops) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

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
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        when {
            loading && items.isEmpty() -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { LoadingIndicator() }
            sections.isEmpty -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Outlined.ShoppingCart, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Nothing to buy", style = MaterialTheme.typography.titleMedium, modifier = Modifier.testTag("list.empty"))
                    Text("Add items as they run out at home.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            else -> LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
                sections.needed.forEach { section ->
                    item(key = "h-${section.id}") {
                        Text(
                            "${section.title} · ${section.items.size}",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp).testTag("list.section.${section.title}"),
                        )
                    }
                    items(section.items, key = { it.id }) { item -> ItemRow(item, shopName = shops.firstOrNull { it.id == item.shopId }?.name) }
                }
                if (sections.bought.isNotEmpty()) {
                    item(key = "h-bought") {
                        Text(
                            "Recently bought (${sections.bought.size}) ${if (showBought) "▾" else "▸"}",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 16.dp, bottom = 4.dp)
                                .testTag("list.bought.toggle")
                                .let { m -> m }.also { },
                        )
                    }
                    if (showBought) items(sections.bought, key = { it.id }) { item -> ItemRow(item, shopName = shops.firstOrNull { it.id == item.shopId }?.name) }
                }
            }
        }
    }
}

@Composable
fun ItemRow(item: ShoppingListItem, shopName: String?) {
    val desc = buildList {
        add(item.name)
        item.quantity?.takeIf { it.isNotBlank() }?.let { add(it) }
        add(if (item.isBought) "bought" else "needed")
        shopName?.let { add(it) }
    }.joinToString(", ")
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)
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
            item.quantity?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}
