import 'dart:async';

import 'package:flash_form/flash_form.dart';
import 'package:flash_form/src/base/base.dart';
import 'package:flash_form/src/base/src/flash_field_decorator.dart';
import 'package:flash_form/src/events/events.dart';
import 'package:flash_form/src/fields/src/list_field/formats/list_field_format.dart';
import 'package:flash_form/src/fields/src/model_field/formats/model_field_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../fields/src/type_field/type_field.dart';

enum FlashFieldType {
  value,
  list,
  type,
  object,
}

abstract class FlashField<TValue, TView>
    with ChangeNotifier
    implements FlashLayout {
  late final int id;

  final FieldFormat fieldFormat;
  final FlashField? parent;
  late final FlashFormContext context;
  List<FieldDecorator>? wrappers;
  List<Validator> validators;
  List<ValidatorResult> validatorResults = [];

  StreamSubscription<FlashFieldEvent>? _eventSubscription;

  FlashField({
    required this.fieldFormat,
    required this.parent,
    this.validators = const [],
    this.wrappers,
  }) {
    context = parent?.context ?? FlashFormContext();
    id = context.generateId();
    context.registerId(id: id, parentId: parent?.id, type: fieldType);
    _eventSubscription = context._eventController.stream.listen((event) {
      onEvent(event);
    });
  }

  TValue? get value;

  void updateValue(TValue? newValue);

  bool get isListItem => context.isListItem(id);

  FlashFieldType get fieldType;

  @override
  Widget build() {
    return FlashFieldWidget(
      field: this,
      builder: (context) {
        var field = fieldFormat.createFieldWidget(this);
        for (var wrapper in wrappers ?? <FieldDecorator<dynamic, dynamic>>[]) {
          field = wrapper.build(field, this);
        }
        return field;
      },
    );
  }

  Future<bool> validate() async {
    validatorResults = await validators.validate(this);

    notifyListeners();

    return validatorResults.isEmpty;
  }

  void clearValidation() {
    validatorResults = [];
    notifyListeners();
  }

  /// イベントが発生したときに呼び出されるコールバック
  void onEvent(FlashFieldEvent event) {}

  void sendEvent(FlashFieldEvent event) {
    context.sendEvent(event);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    context.removeId(id);
    super.dispose();
  }
}

class FlashFormContext {
  FlashFormContext();

  final StreamController<FlashFieldEvent> _eventController =
      StreamController<FlashFieldEvent>.broadcast();

  // 親と子の関係を管理するためのマップ
  final Map<int, List<int>> _idMap = {};

  // 自身のFlashFieldのタイプを管理するためのマップ
  final Map<int, FlashFieldType> _fieldMap = {};

  var maxId = 0;

  int generateId() {
    // final ids = _idMap.keys;
    // for (var id in ids) {
    //   if (id > maxId) {
    //     maxId = id;
    //   }
    // }

    final newId = (maxId + 1);
    maxId = newId;
    return newId;
  }

  void registerId({
    required int id,
    required int? parentId,
    required FlashFieldType type,
  }) {
    _idMap[id] = [];
    _fieldMap[id] = type;

    /// 親のキーを取得
    if (parentId != null) {
      if (!_idMap.containsKey(parentId)) {
        _idMap[parentId] = [];
      }
      _idMap[parentId]!.add(id);
    }
  }

  int? getParentId(int id) {
    final parentIds = _idMap.entries
        .where((entry) => entry.value.contains(id))
        .map((entry) => entry.key);

    if (parentIds.isEmpty) {
      return null;
    }

    if (parentIds.length > 1) {
      throw Exception('Multiple parents found for id: $id');
    }

    return parentIds.first;
  }

  bool isParentChild({
    required int childId,
    required int parentId,
  }) =>
      _idMap[parentId]?.contains(childId) ?? false;

  bool isListItem(int id) {
    final parentId = getParentId(id);
    final parentFieldType = parentId != null ? _fieldMap[parentId] : null;
    return parentFieldType == FlashFieldType.list;
  }

  void removeId(int id) {
    _removeId(id);

    // idを持っているリストから削除する
    for (var entry in _idMap.entries) {
      final children = entry.value;
      if (children.contains(id)) {
        children.remove(id);
      }
    }
  }

  void _removeId(int id) {
    // idに子供がいる場合は遡って削除する
    final children = _idMap[id];
    if (children != null) {
      for (var childId in children) {
        _removeId(childId);
      }
    }

    _idMap.remove(id);
    _fieldMap.remove(id);
  }

  void sendEvent(FlashFieldEvent event) {
    _eventController.add(event);
  }

  int indexOf(int id) {
    final parentId = getParentId(id);
    if (parentId == null) {
      return -1;
    }

    final parentChildren = _idMap[parentId];
    if (parentChildren == null) {
      return -1;
    }

    return parentChildren.indexOf(id);
  }

  /// 木構造のネストの深さを取得する
  int depthOf(int id) {
    final parentId = getParentId(id);
    if (parentId == null) {
      return 0;
    }

    return depthOf(parentId) + 1;
  }

  /// 木構造でルートまでに何回[FlashFieldType]が出現するかを取得する
  int countTypeOf(int id, FlashFieldType type) {
    final parentId = getParentId(id);
    if (parentId == null) {
      return 0;
    }

    if (_fieldMap[parentId] == type) {
      return countTypeOf(parentId, type) + 1;
    }

    return countTypeOf(parentId, type);
  }
}

class ValueField<TValue, TView> extends FlashField<TValue, TView> {
  @override
  TValue? value;
  void Function(FlashFieldEvent event, ValueField<TValue, TView> field)?
      handleEvent;

  ValueField({
    required ValueFieldFormat<TValue, TView> super.fieldFormat,
    required super.parent,
    this.value,
    super.wrappers = const [DefaultValueDecorator()],
    super.validators,
    this.handleEvent,
  });

  @override
  void updateValue(TValue? newValue) {
    value = newValue;
    context.sendEvent(ValueChangeEvent(id: id, value: newValue));
    notifyListeners();
  }

  TView? get viewValue => (fieldFormat as ValueFieldFormat).toView(value);
  TValue? convertViewToValue(TView? viewValue) {
    return (fieldFormat as ValueFieldFormat).fromView(viewValue);
  }

  @override
  void onEvent(FlashFieldEvent event) {
    super.onEvent(event);
    handleEvent?.call(event, this);
  }

  @override
  FlashFieldType get fieldType => FlashFieldType.value;
}

class ListField<TValue, TView> extends FlashField<List<TValue>, List<TView>> {
  List<FlashField<TValue, TView>> children;
  String? Function(List<TValue> value)? validator;
  FlashField<TValue, TView> Function(
      TValue? value, ListField<TValue, TView> parent)? childFactory;
  void Function(FlashFieldEvent event, ListField<TValue, TView>)? handleEvent;

  ListField({
    super.wrappers = const [DefaultListDecorator()],
    required super.parent,
    super.fieldFormat = const ListFieldFormat(),
    required this.children,
    this.childFactory,
    this.validator,
  }) : super();

  @override
  void updateValue(List<TValue>? newValue) {
    children.clear();
    children.addAll(
      newValue?.map(
            (value) => childFactory!(value, this)..updateValue(value),
          ) ??
          List.empty(),
    );
    notifyListeners();
  }

  void addField() {
    if (childFactory == null) {
      return;
    }
    final child = childFactory!(null, this);

    children.add(child);
    notifyListeners();
  }

  void insertField(int index) {
    if (childFactory == null) {
      return;
    }
    final child = childFactory!(null, this);

    children.insert(index, child);
    notifyListeners();
  }

  void removeField(FlashField<TValue, TView> field) {
    children.remove(field);
    context.removeId(field.id);

    notifyListeners();
  }

  void moveField(FlashField<TValue, TView> field, MoveType moveType) {
    final index = children.indexOf(field);
    if (index == -1) {
      return;
    }

    late int newIndex;
    if (moveType == MoveType.up1) {
      newIndex = index - 1;
    } else if (moveType == MoveType.down1) {
      newIndex = index + 1;
    } else if (moveType == MoveType.top) {
      newIndex = 0;
    } else if (moveType == MoveType.bottom) {
      newIndex = children.length - 1;
    }

    if (newIndex < 0 || newIndex >= children.length) {
      return;
    }

    children.remove(field);
    children.insert(newIndex, field);

    notifyListeners();
  }

  void _handleChildEvent(FlashFieldEvent event) {
    if (event is ListItemRemoveEvent &&
        context.isParentChild(
          childId: event.field.id,
          parentId: id,
        )) {
      removeField(event.field as FlashField<TValue, TView>);
    }

    if (event is ListItemAddEvent &&
        context.isParentChild(
          childId: event.field.id,
          parentId: id,
        )) {
      final index = context.indexOf(event.field.id);
      if (index == -1) {
        return;
      }

      final position = event.position;
      if (position == InsertPosition.above) {
        insertField(index);
      } else {
        insertField(index + 1);
      }
    }

    if (event is ListItemMoveEvent &&
        context.isParentChild(
          childId: event.field.id,
          parentId: id,
        )) {
      moveField(event.field as FlashField<TValue, TView>, event.moveType);
    }

    if (event is ListItemRemoveEvent) {}
  }

  @override
  List<TValue>? get value =>
      children.map((e) => e.value).whereType<TValue>().toList();

  @override
  void onEvent(FlashFieldEvent event) {
    super.onEvent(event);
    _handleChildEvent(event);
    handleEvent?.call(event, this);
  }

  @override
  Future<bool> validate() async {
    bool isValid = await super.validate();
    for (var child in children) {
      isValid = await child.validate() && isValid;
    }
    notifyListeners();

    return isValid;
  }

  @override
  FlashFieldType get fieldType => FlashFieldType.list;
}

abstract class ObjectField<T> extends FlashField<T, T> {
  ObjectField({
    super.wrappers = const [DefaultObjectDecorator()],
    required super.parent,
    super.fieldFormat = const ModelFieldFormat(),
  }) : super();

  List<FlashField> get fields;

  List<FlashLayout>? get layout => null;

  T toModel();
  void fromModel(T model);

  @override
  T? get value => toModel();

  @override
  void updateValue(T? newValue) {
    if (newValue == null) {
      return;
    }
    fromModel(newValue);
  }

  @override
  Future<bool> validate() async {
    bool isValid = await super.validate();
    for (var field in fields) {
      isValid = await field.validate() && isValid;
    }
    notifyListeners();

    return isValid;
  }

  @override
  FlashFieldType get fieldType => FlashFieldType.object;
}

typedef FieldFactory<TValue, TView, TOption> = FlashField<TValue, TView>
    Function(
  TOption? value,
  TypeField parent,
);

typedef TypeFactory<TValue, TOption> = TOption Function(TValue value);

typedef TypeFieldEventHandler<TValue, TView, TOption> = void Function(
  FlashFieldEvent event,
  TypeField<TValue, TView, TOption> parent,
);

class TypeField<TValue, TView, TOption> extends FlashField<TValue, TView> {
  final FieldFactory<TValue, TView, TOption> factory;
  final TypeFactory<TValue, TOption> typeFactory;
  final List<TOption> typeOptions;
  final String Function(TOption value) toDisplay;
  TOption? type;
  FlashField<TValue, TView>? selectedField;
  TypeFieldEventHandler<TValue, TView, TOption>? handleEvent;

  TypeField({
    super.wrappers = const [DefaultTypeDecorator()],
    super.fieldFormat = const TypeFieldFormat(),
    required this.typeOptions,
    required this.typeFactory,
    required this.factory,
    required this.type,
    required super.parent,
    required this.toDisplay,
    this.handleEvent,
  }) : super();

  @override
  TValue? get value => selectedField?.value;

  FieldFormat? get selectedFieldFormat {
    return selectedField?.fieldFormat;
  }

  void updateType(TOption? newValue) {
    type = newValue;
    final oldSelected = selectedField;
    if (oldSelected != null) {
      context.removeId(oldSelected.id);
    }

    selectedField = factory(type, this);

    notifyListeners();
  }

  @override
  void updateValue(TValue? newValue) {
    if (newValue == null) {
      type = null;
      selectedField = null;
      notifyListeners();
      return;
    }

    type = typeFactory(newValue);
    selectedField = factory(type, this);
    selectedField?.updateValue(newValue);
    notifyListeners();
  }

  @override
  void onEvent(FlashFieldEvent event) {
    super.onEvent(event);
    handleEvent?.call(event, this);
  }

  @override
  Future<bool> validate() async {
    bool isValid = await super.validate();
    if (selectedField != null) {
      isValid = await selectedField!.validate() && isValid;
    }
    notifyListeners();

    return isValid;
  }

  @override
  FlashFieldType get fieldType => FlashFieldType.type;

  String displayOption(TOption value) => toDisplay(value);

  /// typeによって等値性を判定して、==演算子をオーバーライドする
  @override
  bool operator ==(Object other) {
    if (other is TypeField) {
      return type == other.type && id == other.id;
    }
    return false;
  }

  @override
  int get hashCode => type.hashCode ^ id.hashCode;
}