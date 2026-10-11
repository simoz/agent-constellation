import QtQuick

// Rows for a view over an array that arrives anew with every snapshot. A view
// whose model is the array rebuilds every delegate on each change and resets its
// position, current index and focus; these rows only grow or shrink at the end,
// and delegates read their item from the array by index.
ListModel {
    property int size: 0
    onSizeChanged: {
        if (count > size) remove(size, count - size);
        var rows = [];
        for (var i = count; i < size; i++) rows.push({});
        if (rows.length) append(rows);
    }
}
