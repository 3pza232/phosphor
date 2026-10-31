#include "ui/element.hpp"

#include <utility>

namespace phos::ui {

namespace {

Node make_node(Kind kind, std::string id) {
    Node node;
    node.kind = kind;
    node.id = std::move(id);
    return node;
}

} // namespace

Node& Node::add(Kind child_kind, std::string child_id) {
    children.push_back(make_node(child_kind, std::move(child_id)));
    return children.back();
}

Node& Node::add_text(std::string child_id, std::string text) {
    Node& node = add(Kind::text, std::move(child_id));
    node.props.text = std::move(text);
    return node;
}

Node& Node::add_column(std::string child_id) { return add(Kind::column, std::move(child_id)); }
Node& Node::add_row(std::string child_id) { return add(Kind::row, std::move(child_id)); }

Node& Node::add_box(std::string child_id, std::string title) {
    Node& node = add(Kind::box, std::move(child_id));
    node.props.border = Border::single;
    node.props.padding = Insets{1, 1, 1, 1};
    node.props.title = std::move(title);
    return node;
}

Node& Node::add_divider(std::string child_id) { return add(Kind::divider, std::move(child_id)); }
Node& Node::add_spacer(std::string child_id) { return add(Kind::spacer, std::move(child_id)); }

Node& Node::add_list(std::string child_id, std::vector<std::string> items) {
    Node& node = add(Kind::list, std::move(child_id));
    node.props.items = std::move(items);
    return node;
}

Node& Node::add_option(std::string child_id, std::string text) {
    Node& node = add(Kind::option, std::move(child_id));
    node.props.text = std::move(text);
    return node;
}

Node& Node::add_checkbox(std::string child_id, std::string text) {
    Node& node = add(Kind::checkbox, std::move(child_id));
    node.props.text = std::move(text);
    return node;
}

Node& Node::add_button(std::string child_id, std::string text) {
    Node& node = add(Kind::button, std::move(child_id));
    node.props.text = std::move(text);
    return node;
}

Node& Node::add_field(std::string child_id, std::string text) {
    Node& node = add(Kind::field, std::move(child_id));
    node.props.text = std::move(text);
    return node;
}

Node& Node::add_table(std::string child_id) {
    Node& node = add(Kind::table, std::move(child_id));
    node.focusable = false;
    return node;
}

Node& Node::add_bar(std::string child_id, float ratio) {
    Node& node = add(Kind::bar, std::move(child_id));
    node.props.ratio = ratio;
    return node;
}

Node& Node::add_stat(std::string child_id, std::string label, std::string value) {
    Node& node = add(Kind::stat, std::move(child_id));
    node.props.text = std::move(label);
    node.props.value = std::move(value);
    return node;
}

Node& Node::add_hint(std::string child_id) { return add(Kind::hint, std::move(child_id)); }

Node make_root(std::string id) {
    Node root;
    root.kind = Kind::column;
    root.id = std::move(id);
    root.props.gap = 0;
    root.props.align_h = Align::stretch;
    return root;
}

} // namespace phos::ui