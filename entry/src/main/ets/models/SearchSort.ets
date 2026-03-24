/**
 * 搜索排序方式
 * 支持 relevance / latest / likes / views / latest_topic
 */
export class SearchSortOrder {
  readonly key: string;
  readonly orderValue: string;
  readonly label: Resource;

  private constructor(key: string, orderValue: string, label: Resource) {
    this.key = key;
    this.orderValue = orderValue;
    this.label = label;
  }

  static readonly RELEVANCE: SearchSortOrder =
    new SearchSortOrder('relevance', '', $r('app.string.search_sort_relevance'));

  static readonly LATEST: SearchSortOrder =
    new SearchSortOrder('latest', 'latest', $r('app.string.search_sort_latest'));

  static readonly LIKES: SearchSortOrder =
    new SearchSortOrder('likes', 'likes', $r('app.string.search_sort_likes'));

  static readonly VIEWS: SearchSortOrder =
    new SearchSortOrder('views', 'views', $r('app.string.search_sort_views'));

  static readonly LATEST_TOPIC: SearchSortOrder =
    new SearchSortOrder('latest_topic', 'latest_topic', $r('app.string.search_sort_latest_topic'));

  static values(): SearchSortOrder[] {
    return [
      SearchSortOrder.RELEVANCE,
      SearchSortOrder.LATEST,
      SearchSortOrder.LIKES,
      SearchSortOrder.VIEWS,
      SearchSortOrder.LATEST_TOPIC
    ];
  }

  static fromKey(raw: string): SearchSortOrder {
    const values: SearchSortOrder[] = SearchSortOrder.values();
    for (let i: number = 0; i < values.length; i++) {
      const item: SearchSortOrder = values[i];
      if (item.key === raw) {
        return item;
      }
    }
    return SearchSortOrder.RELEVANCE;
  }

  static fromOrderValue(raw: string): SearchSortOrder {
    const values: SearchSortOrder[] = SearchSortOrder.values();
    for (let i: number = 0; i < values.length; i++) {
      const item: SearchSortOrder = values[i];
      if (item.key === raw || item.orderValue === raw) {
        return item;
      }
    }
    return SearchSortOrder.RELEVANCE;
  }
}
